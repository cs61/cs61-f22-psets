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

int io61_seek(io61_file* f, off_t pos);

int io61_readc(io61_file* f);
int io61_writec(io61_file* f, int ch);

ssize_t io61_read(io61_file* f, unsigned char* buf, size_t sz);
ssize_t io61_write(io61_file* f, const unsigned char* buf, size_t sz);

int io61_flush(io61_file* f);

int fd_open_check(const char* filename, int mode);
FILE* stdio_open_check(const char* filename, int mode);


struct io61_args {
    size_t file_size = SIZE_MAX;        // `-s`: file size
    size_t block_size = 0;              // `-b`: block size
    size_t initial_offset = 0;          // `-p`: initial offset
    size_t stride = 1024;               // `-t`: stride
    bool lines = false;                 // `-l`: read by lines
    bool flush = false;                 // `-F`: flush output
    bool quiet = false;                 // `-q`: ignore errors
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
    bool nonblocking = false;           // `-n`: nonblocking

    explicit io61_args(const char* opts, size_t block_size = 0);

    io61_args& set_block_size(size_t bs);
    io61_args& set_seed(unsigned seed);
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

#endif
