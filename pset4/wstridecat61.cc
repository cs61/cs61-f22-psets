#include "io61.hh"

// Usage: ./wstridecat61 [-b BLOCKSIZE] [-t STRIDE] [-o OUTFILE] [FILE]
//    Copies the input FILE to OUTFILE in blocks, shuffling its
//    contents. Reads FILE sequentially, but writes to its output in a
//    strided access pattern. Default BLOCKSIZE is 1 and default STRIDE is
//    1024. This means the output file's bytes are written in the sequence
//    0, 1024, 2048, ..., 1, 1025, 2049, ..., etc.

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("b:t:s:o:p:", 1).parse(argc, argv);

    // Allocate buffer, open files, measure file sizes
    unsigned char* buf = new unsigned char[args.block_size];
    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);
    io61_file* outf = io61_open_check(args.output_file,
                                      O_WRONLY | O_CREAT | O_TRUNC);
    if (io61_seek(outf, 0) < 0) {
        fprintf(stderr, "wstridecat61: output file is not seekable\n");
        exit(1);
    }

    if ((ssize_t) args.file_size < 0) {
        args.file_size = io61_filesize(inf);
    }
    if ((ssize_t) args.file_size < 0) {
        fprintf(stderr, "wstridecat61: need `-s SIZE` argument\n");
        exit(1);
    }

    // Copy file data
    size_t pos = 0, written = 0;
    while (written < args.file_size) {
        // Copy a block
        ssize_t nr = io61_read(inf, buf, args.block_size);
        if (nr <= 0) {
            break;
        }

        ssize_t nw = io61_write(outf, buf, nr);
        assert(nw == nr);

        written += nw;

        // Move `outf` file position to next stride
        pos += args.stride;
        if (pos >= args.file_size) {
            pos = (pos % args.stride) + args.block_size;
            if (pos + args.block_size > args.stride) {
                args.block_size = args.stride - pos;
            }
        }
        int r = io61_seek(outf, pos);
        assert(r == 0);

        args.after_write(outf);
    }

    io61_close(inf);
    io61_close(outf);
    delete[] buf;
}
