#include "io61.hh"

// Usage: ./blockwriteat61 [-b BLOCKSIZE] [-p POS] [-o OUTFILE] [FILE]
//    Copies the input FILE to standard output in blocks,
//    starting at offset POS.
//    Reads using stdio and writes using io61.
//    Default BLOCKSIZE is 4096.

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("b:o:i:p:Fy", 4096).parse(argc, argv);

    // Allocate buffer, open files
    unsigned char* buf = new unsigned char[args.block_size];
    FILE* inf = stdio_open_check(args.input_file, O_RDONLY);
    io61_file* outf = io61_open_check(args.output_file, O_WRONLY | O_CREAT);
    args.after_open(inf, O_RDONLY);

    int r = io61_seek(outf, args.initial_offset);
    assert(r == 0);

    // Copy file data
    while (true) {
        ssize_t nr = fread(buf, 1, args.block_size, inf);
        if (nr <= 0) {
            break;
        }

        ssize_t nw = io61_write(outf, buf, nr);
        assert(nw == nr);

        args.after_write(outf);
    }

    fclose(inf);
    io61_close(outf);
    delete[] buf;
}
