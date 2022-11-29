#include "io61.hh"
#include <ctime>
#include <csignal>
#include <cerrno>
#include <sys/time.h>
#include <sys/resource.h>

// helpers.cc
//    The io61_args() structure parses command line arguments.
//    The profile functions measure how much time and memory are used
//    by your code.


// fd_open_check(filename, mode)
//    Like `io61_open_check`, but returns a file descriptor.

int fd_open_check(const char* filename, int mode) {
    int fd;
    if (filename) {
        fd = open(filename, mode, 0666);
    } else if ((mode & O_ACCMODE) == O_RDONLY) {
        return STDIN_FILENO;
    } else {
        return STDOUT_FILENO;
    }
    if (fd < 0) {
        fprintf(stderr, "%s: %s\n", filename, strerror(errno));
        exit(1);
    }
    return fd;
}


// stdio_open_check(filename, mode)
//    Like `io61_open_check`, but returns a stdio file.

FILE* stdio_open_check(const char* filename, int mode) {
    int fd = fd_open_check(filename, mode);
    if (filename) {
        const char* modestr;
        if ((mode & O_ACCMODE) == O_RDONLY) {
            modestr = "rb";
        } else if ((mode & O_ACCMODE) == O_WRONLY) {
            modestr = "wb";
        } else {
            modestr = "r+b";
        }
        return fdopen(fd, modestr);
    } else if ((mode & O_ACCMODE) == O_RDONLY) {
        return stdin;
    } else {
        return stdout;
    }
}


// monotonic_timestamp()
//    Returns the current monotonic timestamp.

double monotonic_timestamp() {
    timespec t;
    int r = clock_gettime(CLOCK_MONOTONIC, &t);
    assert(r == 0);
    return t.tv_sec + t.tv_nsec * 1e-9;
}


// io61_args functions

io61_args::io61_args(const char* opts_, size_t block_size_)
    : block_size(block_size_), opts(opts_) {
}

io61_args& io61_args::set_block_size(size_t block_size_) {
    this->block_size = block_size_;
    return *this;
}

io61_args& io61_args::set_seed(unsigned seed_) {
    this->engine.seed(seed_);
    this->seed = seed_;
    return *this;
}

io61_args& io61_args::set_noperations(size_t nop_) {
    this->noperations = nop_;
    return *this;
}

io61_args& io61_args::set_nthreads(int n) {
    this->nthreads = n;
    return *this;
}

io61_args& io61_args::set_ndistinguished_threads(int n) {
    this->ndistinguished_threads = n;
    return *this;
}

extern "C" {
static void sigalrm_handler(int) {
}
}

io61_args& io61_args::parse(int argc, char** argv) {
    this->program_name = argv[0];
    size_t block_size_ = this->block_size;
    double alarm_interval = 0;

    int arg;
    char* endptr;
    while ((arg = getopt(argc, argv, this->opts)) != -1) {
        switch (arg) {
        case 's':
            this->file_size = (size_t) strtoul(optarg, &endptr, 0);
            if (endptr == optarg || *endptr) {
                goto usage;
            }
            break;
        case 'b':
            block_size_ = (size_t) strtoul(optarg, &endptr, 0);
            if (block_size_ == 0 || endptr == optarg || *endptr) {
                goto usage;
            }
            break;
        case 't':
            this->stride = (size_t) strtoul(optarg, &endptr, 0);
            if (this->stride == 0 || endptr == optarg || *endptr) {
                goto usage;
            }
            break;
        case 'l':
            this->lines = true;
            break;
        case 'F':
            this->flush = true;
            break;
        case 'y':
            ++this->yield;
            break;
        case 'K':
            this->nonblocking = true;
            break;
        case 'q':
            this->quiet = true;
            break;
        case 'i':
            this->input_files.push_back(optarg);
            break;
        case 'o':
            this->output_files.push_back(optarg);
            break;
        case 'p':
            this->initial_offset = (size_t) strtoul(optarg, &endptr, 0);
            if (endptr == optarg || *endptr) {
                goto usage;
            }
            break;
        case 'M':
            this->modify = true;
            break;
        case 'r': {
            unsigned long n = strtoul(optarg, &endptr, 0);
            if (endptr == optarg || *endptr) {
                goto usage;
            }
            this->engine.seed(n);
            break;
        }
        case 'D':
            this->delay = strtod(optarg, &endptr);
            if (endptr == optarg || *endptr) {
                goto usage;
            }
            break;
        case 'a':
            alarm_interval = strtod(optarg, &endptr);
            if (endptr == optarg || *endptr) {
                goto usage;
            }
            break;
        case 'B':
            this->pipebuf_size = (size_t) strtoul(optarg, &endptr, 0);
            if (endptr == optarg || *endptr) {
                goto usage;
            }
            break;
        case 'j': {
            int n = strtol(optarg, &endptr, 0);
            if (endptr == optarg || *endptr || n <= 0) {
                goto usage;
            }
            this->nthreads = n;
            break;
        }
        case 'J': {
            int n = strtol(optarg, &endptr, 0);
            if (endptr == optarg || *endptr || n < 0) {
                goto usage;
            }
            this->ndistinguished_threads = n;
            break;
        }
        case 'n':
            this->noperations = (size_t) strtoul(optarg, &endptr, 0);
            if (endptr == optarg || *endptr) {
                goto usage;
            }
            break;
        case '#':
        default:
            goto usage;
        }
    }

    if (alarm_interval > 0) {
        struct sigaction act;
        act.sa_handler = sigalrm_handler;
        sigemptyset(&act.sa_mask);
        act.sa_flags = 0;
        int r = sigaction(SIGALRM, &act, nullptr);
        assert(r == 0);

        double sec = floor(alarm_interval);
        timeval tv = { (int) sec, (int) ((alarm_interval - sec) * 1e6) };
        itimerval timer = { tv, tv };
        r = setitimer(ITIMER_REAL, &timer, nullptr);
        assert(r == 0);
    }
    for (int i = optind; i < argc; ++i) {
        this->input_files.push_back(argv[i]);
    }
    if (this->input_files.empty()) {
        this->input_files.push_back(nullptr);
    } else if (this->input_files.size() == 1) {
        this->input_file = this->input_files[0];
    } else if (!strchr(this->opts, '#')) {
        goto usage;
    }
    if (this->output_files.empty()) {
        this->output_files.push_back(nullptr);
    } else if (this->output_files.size() == 1) {
        this->output_file = this->output_files[0];
    } else if (!strstr(this->opts, "##")) {
        goto usage;
    }
    if (this->ndistinguished_threads > this->nthreads) {
        goto usage;
    }
    this->block_size = block_size_;
    return *this;

 usage:
    this->usage();
    exit(1);
}

void io61_args::usage() {
    fprintf(stderr, "Usage: %s [OPTIONS] [FILE]%s\nOptions:\n",
            this->program_name, strchr(this->opts, '#') ? "..." : "");
    if (strchr(this->opts, 'i')) {
        fprintf(stderr, "    -i FILE       Read input from FILE\n");
    }
    if (strchr(this->opts, 'o')) {
        fprintf(stderr, "    -o FILE       Write output to FILE\n");
    }
    if (strchr(this->opts, 'q')) {
        fprintf(stderr, "    -q            Ignore errors\n");
    }
    if (strchr(this->opts, 's')) {
        fprintf(stderr, "    -s SIZE       Set size written\n");
    }
    if (strchr(this->opts, 'b')) {
        if (this->block_size) {
            fprintf(stderr, "    -b BLOCKSIZE  Set block size (default %zu)\n", this->block_size);
        } else {
            fprintf(stderr, "    -b BLOCKSIZE  Set block size\n");
        }
    }
    if (strchr(this->opts, 't')) {
        fprintf(stderr, "    -t STRIDE     Set stride (default %zu)\n", this->stride);
    }
    if (strchr(this->opts, 'p')) {
        fprintf(stderr, "    -p POS        Set initial file position\n");
    }
    if (strchr(this->opts, 'l')) {
        fprintf(stderr, "    -l            Output by lines\n");
    }
    if (strchr(this->opts, 'F')) {
        fprintf(stderr, "    -F            Flush after each write\n");
    }
    if (strchr(this->opts, 'y')) {
        fprintf(stderr, "    -y            Yield after each write\n");
    }
    if (strchr(this->opts, 'B')) {
        fprintf(stderr, "    -B BUFSIZ     Set input pipe buffer size on Linux\n");
    }
    if (strchr(this->opts, 'r')) {
        fprintf(stderr, "    -r            Set random seed (default %u)\n", this->seed);
    }
    if (strchr(this->opts, 'D')) {
        fprintf(stderr, "    -D DELAY      Delay before starting\n");
    }
    if (strchr(this->opts, 'a')) {
        fprintf(stderr, "    -a TIME       Set interval timer\n");
    }
    if (strchr(this->opts, 'K')) {
        fprintf(stderr, "    -K            Use nonblocking I/O\n");
    }
    if (strchr(this->opts, 'j')) {
        fprintf(stderr, "    -j N          Start N threads\n");
    }
    if (strchr(this->opts, 'J')) {
        fprintf(stderr, "    -J N          Use N distinguished threads\n");
    }
    if (strchr(this->opts, 'n')) {
        fprintf(stderr, "    -n N          Perform N operations\n");
    }
    if (strchr(this->opts, 'M')) {
        fprintf(stderr, "    -M            Modify input file in place\n");
    }
}

void io61_args::after_open() {
    if (this->delay > 0) {
        double now = monotonic_timestamp();
        double end = now + this->delay;
        while (now < end) {
            usleep((unsigned) ((end - now) * 1e6));
            now = monotonic_timestamp();
        }
        this->delay = 0;
    }
}

void io61_args::after_open(int fd, int mode) {
    (void) mode;
#ifdef F_SETPIPE_SZ
    if (this->pipebuf_size > 0) {
        int r = fcntl(fd, F_SETPIPE_SZ, this->pipebuf_size);
        (void) r;
    }
#endif
    if (this->nonblocking) {
        int r = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        (void) r;
    }
    this->after_open();
}

void io61_args::after_open(io61_file* f, int mode) {
    this->after_open(io61_fileno(f), mode);
}

void io61_args::after_open(FILE* f, int mode) {
    this->after_open(fileno(f), mode);
}

void io61_args::after_write(int fd) {
    (void) fd;
    if (this->yield > 0) {
        usleep(this->yield);
    }
}

void io61_args::after_write(io61_file* f) {
    if (this->flush) {
        int r = io61_flush(f);
        assert(r == 0);
    }
    if (this->yield > 0) {
        usleep(this->yield);
    }
}

void io61_args::after_write(FILE* f) {
    if (this->flush) {
        int r = fflush(f);
        assert(r == 0);
    }
    if (this->yield > 0) {
        usleep(this->yield);
    }
}


namespace {

struct io61_profiler {
    double begin_at;
    io61_profiler();
    ~io61_profiler();
};

static io61_profiler profiler_instance;

io61_profiler::io61_profiler() {
    this->begin_at = monotonic_timestamp();
}

io61_profiler::~io61_profiler() {
    // Measure elapsed real, user, and system times, and report the result
    // as JSON to file descriptor 100 if it’s available.

    double real_elapsed = monotonic_timestamp() - this->begin_at;

    struct rusage usage;
    int r = getrusage(RUSAGE_SELF, &usage);
    assert(r == 0);

    struct rusage cusage;
    r = getrusage(RUSAGE_CHILDREN, &cusage);
    assert(r == 0);
    timeradd(&usage.ru_utime, &cusage.ru_utime, &usage.ru_utime);
    timeradd(&usage.ru_stime, &cusage.ru_stime, &usage.ru_stime);

    long maxrss = usage.ru_maxrss + cusage.ru_maxrss;
#if __MACH__
    maxrss = (maxrss + 1023) / 1024;
#endif

    char buf[1000];
    ssize_t len = snprintf(buf, sizeof(buf),
        "{\"time\":%.6f, \"utime\":%ld.%06ld, \"stime\":%ld.%06ld, \"maxrss\":%ld}\n",
        real_elapsed,
        usage.ru_utime.tv_sec, (long) usage.ru_utime.tv_usec,
        usage.ru_stime.tv_sec, (long) usage.ru_stime.tv_usec,
        maxrss);

    off_t off = lseek(100, 0, SEEK_CUR);
    int fd = (off != (off_t) -1 || errno == ESPIPE ? 100 : STDERR_FILENO);
    if (fd == STDERR_FILENO && !getenv("TIMING")) {
        return;
    } else if (fd == STDERR_FILENO) {
        fflush(stderr);
    }
    while (true) {
        ssize_t nw = write(fd, buf, len);
        if (nw == len) {
            break;
        }
        assert(nw == -1 && (errno == EINTR || errno == EAGAIN));
    }
}

}
