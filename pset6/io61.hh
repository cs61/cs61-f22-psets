#ifndef IO61_HH
#define IO61_HH
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cassert>
#include <vector>
#include <random>
#include <unistd.h>
#include <fcntl.h>
#include <sched.h>

struct io61_file;

io61_file* io61_fdopen(int fd, int mode);
io61_file* io61_open_check(const char* filename, int mode);
int io61_fileno(io61_file* f);
int io61_close(io61_file* f);

off_t io61_filesize(io61_file* f);

int io61_seek(io61_file* f, off_t off);

int io61_readc(io61_file* f);
int io61_writec(io61_file* f, int c);

ssize_t io61_read(io61_file* f, unsigned char* buf, size_t sz);
ssize_t io61_write(io61_file* f, const unsigned char* buf, size_t sz);

ssize_t io61_pread(io61_file* f, unsigned char* buf, size_t sz,
                   off_t off);
ssize_t io61_pwrite(io61_file* f, const unsigned char* buf, size_t sz,
                    off_t off);

int io61_try_lock(io61_file* f, off_t start, off_t len, int locktype);
int io61_lock(io61_file* f, off_t start, off_t len, int locktype);
int io61_unlock(io61_file* f, off_t start, off_t len);

int io61_flush(io61_file* f);

int fd_open_check(const char* filename, int mode);
FILE* stdio_open_check(const char* filename, int mode);
double monotonic_timestamp();


struct io61_args {
    size_t file_size = SIZE_MAX;        // `-s`: file size
    size_t block_size = 0;              // `-b`: block size
    size_t initial_offset = 0;          // `-p`: initial offset
    size_t stride = 1024;               // `-t`: stride
    bool lines = false;                 // `-l`: read by lines
    bool flush = false;                 // `-F`: flush output
    bool quiet = false;                 // `-q`: ignore errors
    bool modify = false;                // `-M`: modify in place
    unsigned yield = 0;                 // `-y`: yield after output
    const char* output_file = nullptr;  // `-o`: output file
    const char* input_file = nullptr;   // input file
    std::vector<const char*> input_files;   // all input files
    std::vector<const char*> output_files;  // all output files
    const char* program_name;           // name of program
    const char* opts;                   // options string
    std::mt19937 engine;                // source of randomness
    unsigned seed;                      // `-r`: random seed
    double delay = 0.0;                 // `-D`: delay
    size_t pipebuf_size = 0;            // `-B`: pipe buffer size
    bool nonblocking = false;           // `-K`: nonblocking
    int nthreads = 1;                   // `-j`: number of threads
    int ndistinguished_threads = 0;     // `-J`: # distinguished threads
    size_t noperations = 0;             // `-n`: number of operations

    explicit io61_args(const char* opts, size_t block_size = 0);

    io61_args& set_block_size(size_t bs);
    io61_args& set_seed(unsigned seed);
    io61_args& set_noperations(size_t nops);
    io61_args& set_nthreads(int n);
    io61_args& set_ndistinguished_threads(int n);
    io61_args& parse(int argc, char** argv);

    void usage();

    // Call this after opening files (`-B`/`-D`).
    void after_open();
    void after_open(int fd, int mode);
    void after_open(io61_file* f, int mode);
    void after_open(FILE* f, int mode);
    // Call this after writing one block of data.
    void after_write(int fd);
    void after_write(io61_file* f);
    void after_write(FILE* f);
};


// convenience versions
inline ssize_t io61_read(io61_file* f, char* buf, size_t sz) {
    return io61_read(f, reinterpret_cast<unsigned char*>(buf), sz);
}

inline ssize_t io61_write(io61_file* f, const char* buf, size_t sz) {
    return io61_write(f, reinterpret_cast<const unsigned char*>(buf), sz);
}

inline ssize_t io61_pread(io61_file* f, char* buf, size_t sz,
                          off_t off) {
    return io61_pread(f, reinterpret_cast<unsigned char*>(buf), sz, off);
}

inline ssize_t io61_pwrite(io61_file* f, const char* buf, size_t sz,
                           off_t off) {
    return io61_pwrite(f, reinterpret_cast<const unsigned char*>(buf), sz, off);
}

#endif
