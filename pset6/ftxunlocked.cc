#include "ftxdb.hh"
#include <sys/resource.h>
#include <thread>
#include <mutex>

// Usage: ./ftxunlocked [-j NTHREADS] [-n NOPS] [FILE]
//    Perform NOPS * NTHREADS “bank transfers” within FILE.
//    This versiond oes not acquire file locks, and thus cannot be made
//    correct.

static void transfer_thread(ftx_db& db, size_t nops, size_t& opcount,
                            unsigned seed) {
    // Obtain a source of random account numbers
    std::default_random_engine randomness(seed);
    std::uniform_int_distribution pick_account(size_t(0), db.naccounts - 1);
    std::normal_distribution pick_amount(100.0, 10.0);

    size_t i = 0;
    while (i != nops) {
        // Pick two random accounts for transfer
        size_t aindex[2] = {
            pick_account(randomness), pick_account(randomness)
        };
        if (aindex[0] == aindex[1]) {
            continue;
        }

        // Lock both accounts; prevent deadlock with lock ordering
        ftx_acct acct1{db, aindex[0]};
        ftx_acct acct2{db, aindex[1]};

        // Read current balances
        long bal[2];
        acct1.read(nullptr, 0, &bal[0]);
        acct2.read(nullptr, 0, &bal[1]);

        // Model network delay or heavy computation
        usleep(1);

        // Compute amount to transfer
        long delta = std::min(bal[0], (long) pick_amount(randomness));
        delta = std::min(delta, 9999999 - bal[1]);
        bal[0] -= delta;
        bal[1] += delta;

        // Update balances
        acct1.write(bal[0]);
        acct2.write(bal[1]);

        ++i;
    }
    opcount = i;
}


int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("i:D:j:n:").set_nthreads(4)
        .set_noperations(100'000)
        .parse(argc, argv);

    // Allocate buffer, open files
    ftx_db* db = ftx_db::open_args(args);
    args.after_open(db->f, O_RDWR);
    std::random_device seed_randomness;
    double start_time = monotonic_timestamp();

    // Run transfers
    std::vector<std::thread> th(args.nthreads);
    std::vector<size_t> opcounts(args.nthreads, 0);
    for (int i = 0; i != args.nthreads; ++i) {
        th[i] = std::thread(transfer_thread, std::ref(*db),
                            args.noperations, std::ref(opcounts[i]),
                            seed_randomness());
    }

    size_t totalops = 0;
    for (int i = 0; i != args.nthreads; ++i) {
        th[i].join();
        totalops += opcounts[i];
    }

    // Flush and close
    delete db;

    double end_time = monotonic_timestamp();
    struct rusage usage;
    int r = getrusage(RUSAGE_SELF, &usage);
    assert(r == 0);
    fprintf(stderr, "%d %s, %zu %s, %d.%06ds CPU time, %.6fs real time\n",
            args.nthreads, args.nthreads == 1 ? "thread" : "threads",
            totalops, totalops == 1 ? "operation" : "operations",
            (int) usage.ru_utime.tv_sec, (int) usage.ru_utime.tv_usec,
            end_time - start_time);
}
