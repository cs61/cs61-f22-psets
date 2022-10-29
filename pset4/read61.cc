#include "io61.hh"

// Usage: ./read61 [-s SIZE] [-o OUTFILE] [FILE]
//    Copies the input FILE to OUTFILE one character at a time.
//    Reads using io61 and writes using stdio.

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("s:o:i:Fy").parse(argc, argv);

    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);
    FILE* outf = stdio_open_check(args.output_file,
                                  O_WRONLY | O_CREAT | O_TRUNC);
    args.after_open(outf, O_WRONLY);

    while (args.file_size != 0) {
        int ch = io61_readc(inf);
        if (ch == EOF) {
            break;
        }

        int r = fputc(ch, outf);
        assert(r == 0);
        --args.file_size;

        args.after_write(outf);
    }

    io61_close(inf);
    fclose(outf);
}
