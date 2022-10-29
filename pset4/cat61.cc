#include "io61.hh"

// Usage: ./cat61 [-s SIZE] [-o OUTFILE] [FILE]
//    Copies the input FILE to OUTFILE one character at a time.

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("s:o:i:D:a:Fy").parse(argc, argv);

    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);
    io61_file* outf = io61_open_check(args.output_file,
                                      O_WRONLY | O_CREAT | O_TRUNC);
    args.after_open();

    while (args.file_size != 0) {
        int ch = io61_readc(inf);
        if (ch == EOF) {
            break;
        }

        int r = io61_writec(outf, ch);
        assert(r == 0);
        --args.file_size;

        args.after_write(outf);
    }

    io61_close(inf);
    io61_close(outf);
}
