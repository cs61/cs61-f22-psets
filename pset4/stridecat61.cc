#include "io61.hh"

// Usage: ./stridecat61 [-b BLOCKSIZE] [-t STRIDE] [-s SIZE]
//                      [-p POSITION] [-o OUTFILE] [FILE]
//    Copies the input FILE to OUTFILE in blocks, shuffling its
//    contents. Reads FILE in a strided access pattern, but writes
//    sequentially. Default BLOCKSIZE is 1 and default STRIDE is
//    1024. This means the input file's bytes are read in the sequence
//    0, 1024, 2048, ..., 1, 1025, 2049, ..., etc.

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("b:t:s:o:p:", 1).parse(argc, argv);

    // Allocate buffer, open files, measure file sizes
    unsigned char* buf = new unsigned char[args.block_size];

    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);

    if ((ssize_t) args.file_size < 0) {
        args.file_size = io61_filesize(inf);
    }
    if ((ssize_t) args.file_size < 0) {
        fprintf(stderr, "stridecat61: can't get size of input file\n");
        exit(1);
    }
    if (io61_seek(inf, 0) < 0) {
        fprintf(stderr, "stridecat61: input file is not seekable\n");
        exit(1);
    }

    io61_file* outf = io61_open_check(args.output_file,
                                      O_WRONLY | O_CREAT | O_TRUNC);

    // Copy file data
    size_t pos = args.initial_offset;
    size_t written = 0;
    while (written < args.file_size) {
        // Move to current position
        int r = io61_seek(inf, pos);
        assert(r >= 0);

        // Copy a block
        ssize_t nr = io61_read(inf, buf, args.block_size);
        if (nr <= 0) {
            break;
        }

        ssize_t nw = io61_write(outf, buf, nr);
        assert(nw == nr);

        written += nw;

        // Move `inf` file position to next stride
        pos += args.stride;
        if (pos >= args.file_size) {
            pos = (pos % args.stride) + args.block_size;
            if (pos + args.block_size > args.stride) {
                args.block_size = args.stride - pos;
            }
        }

        args.after_write(outf);
    }

    io61_close(inf);
    io61_close(outf);
    delete[] buf;
}
