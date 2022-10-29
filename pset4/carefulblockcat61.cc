#include "io61.hh"

// Usage: ./blockcat61 [-b BLOCKSIZE] [-o OUTFILE] [FILE]
//    Copies the input FILE to standard output in blocks.
//    Default BLOCKSIZE is 4096.
//    Unlike `blockcat61`, this program retries on recoverable
//    errors (EINTR and EAGAIN).

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("b:o:i:D:a:B:nFy", 4096).parse(argc, argv);

    // Allocate buffer, open files
    unsigned char* buf = new unsigned char[args.block_size];
    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);
    io61_file* outf = io61_open_check(args.output_file,
                                      O_WRONLY | O_CREAT | O_TRUNC);
    args.after_open(inf, O_RDONLY);
    args.after_open(outf, O_WRONLY);

    // Copy file data
    while (true) {
    reread:
        ssize_t nr = io61_read(inf, buf, args.block_size);
        if (nr == -1 && (errno == EINTR || errno == EAGAIN)) {
            goto reread;
        } else if (nr <= 0) {
            break;
        }

        ssize_t pos = 0;
        while (pos != nr) {
        rewrite:
            ssize_t nw = io61_write(outf, buf + pos, nr - pos);
            if (nw == -1 && (errno == EINTR || errno == EAGAIN)) {
                goto rewrite;
            }
            assert(nw > 0);
            pos += nw;
        }

        args.after_write(outf);
    }

    io61_close(inf);
    io61_close(outf);
    delete[] buf;
}
