#include "io61.hh"

// Usage: ./carefulcat61 [-s SIZE] [-o OUTFILE] [-n] [FILE]
//    Copies the input FILE to OUTFILE one character at a time.
//    Unlike `cat61`, this program retries on recoverable errors
//    (EINTR and EAGAIN).

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("s:o:i:D:B:a:nFy").parse(argc, argv);

    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);
    io61_file* outf = io61_open_check(args.output_file,
                                      O_WRONLY | O_CREAT | O_TRUNC);
    args.after_open();

    while (args.file_size != 0) {
    reread:
        errno = 0;
        int ch = io61_readc(inf);
        if (ch == EOF && (errno == EINTR || errno == EAGAIN)) {
            goto reread;
        } else if (ch == EOF) {
            break;
        }

    rewrite:
        errno = 0;
        int r = io61_writec(outf, ch);
        if (r == EOF && (errno == EINTR || errno == EAGAIN)) {
            goto rewrite;
        }
        assert(r == 0);
        --args.file_size;

        args.after_write(outf);
    }

    io61_close(inf);
    io61_close(outf);
}
