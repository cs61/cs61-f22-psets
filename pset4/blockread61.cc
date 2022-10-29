#include "io61.hh"

// Usage: ./blockread61 [-b BLOCKSIZE] [-o OUTFILE] [FILE]
//    Copies the input FILE to standard output in blocks.
//    Reads using io61 and writes using stdio.
//    Default BLOCKSIZE is 4096.

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("b:o:i:D:Fy", 4096).parse(argc, argv);

    // Allocate buffer, open files
    unsigned char* buf = new unsigned char[args.block_size];
    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);
    FILE* outf = stdio_open_check(args.output_file,
                                  O_WRONLY | O_CREAT | O_TRUNC);
    args.after_open(outf, O_WRONLY);

    // Copy file data
    while (true) {
        ssize_t nr = io61_read(inf, buf, args.block_size);
        if (nr <= 0) {
            break;
        }

        ssize_t nw = fwrite(buf, 1, nr, outf);
        assert(nw == nr);

        args.after_write(outf);
    }

    io61_close(inf);
    fclose(outf);
    delete[] buf;
}
