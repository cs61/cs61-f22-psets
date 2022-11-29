#include "ftxdb.hh"
#include <charconv>
#include <cstdlib>

ftx_db::ftx_db(io61_file* f_) {
    this->f = f_;
    size_t sz = io61_filesize(this->f);
    assert(sz % this->asize == 0);
    this->naccounts = sz / this->asize;

    // ensure data is cached
    ftx_acct acct(*this, 0);
    char buf[ftx_db::max_asize];
    long balance = -1;
    int r = acct.read(buf, sizeof(buf), &balance);
    assert(r == 0);
    assert(balance >= 0);
}

ftx_db::~ftx_db() {
    io61_close(this->f);
}


ftx_db* ftx_db::open_args(const io61_args& args) {
    const char* original = args.input_file;
    if (original == nullptr) {
        original = "accounts.fdb";
    }
    const char* copy = nullptr;
    if (args.modify) {
        copy = original;
    } else if (args.input_files.size() > 1) {
        copy = args.input_files[1];
    } else {
        copy = "/tmp/newaccounts.fdb";
    }
    if (strcmp(original, copy) != 0) {
        const char* allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789~./-_";
        // check filenames
        if (strspn(original, allowed) != strlen(original)
            || strspn(copy, allowed) != strlen(copy)) {
            fprintf(stderr, "Bad filenames\n");
            exit(1);
        }
        std::string command = std::string("cp ") + std::string(original) + std::string(" ") + std::string(copy);
        int r = system(command.c_str());
        assert(r == 0);
    }
    io61_file* f = io61_open_check(copy, O_RDWR);
    return new ftx_db(f);
}


int ftx_acct::parse(const char* buf, size_t len, const ftx_db& db,
                    char* namebuf, size_t namesz, long* balance) {
    if (len != db.asize) {
        errno = EINVAL;
        return -1;
    }

    // Store name, if requested
    if (namebuf && namesz > 0) {
        size_t off = 0;
        while (off != namesz - 1 && off != db.asize && buf[off] != ' ') {
            namebuf[off] = buf[off];
            ++off;
        }
        namebuf[off] = '\0';
    }

    // Store balance, if requested
    if (balance) {
        // skip spaces and `+`
        size_t off = db.balance_offset;
        while (off != db.asize && buf[off] == ' ') {
            ++off;
        }
        if (off != db.asize && buf[off] == '+') {
            ++off;
        }
        // parse balance
        long b = 0;
        auto fcr = std::from_chars(&buf[off], &buf[db.asize], b, 10);
        if (fcr.ec != std::errc()) {
            errno = static_cast<int>(fcr.ec);
            return -1;
        }
        *balance = b;
    }

    return 0;
}

std::pair<const char*, size_t> ftx_acct::unparse(char* buf, size_t len,
        const ftx_db& db, long balance) {
    assert(len >= db.balance_size * 2 + 1);
    size_t off = db.balance_size;
    size_t lastoff = off + db.balance_size;
    memset(buf, ' ', off);
    auto tcr = std::to_chars(&buf[off], &buf[lastoff], balance, 10);
    if (tcr.ec != std::errc()) {
        // space for balance is too small; return -1
        errno = static_cast<int>(tcr.ec);
        return std::make_pair(buf, 0);
    }
    *tcr.ptr++ = '\n';
    return std::make_pair(tcr.ptr - db.balance_size - 1, db.balance_size + 1);
}
