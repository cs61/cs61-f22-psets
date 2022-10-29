#include "io61.hh"

// Usage: ./reordercat61 [-b BLOCKSIZE] [-r RANDOMSEED] [-s SIZE]
//                       [-o OUTFILE] [FILE]
//    Copies the input FILE to OUTFILE in blocks. The blocks are
//    transferred in random order, but the resulting output file
//    should be the same as the input. Default BLOCKSIZE is 4096.

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("b:r:s:o:i:", 4096).set_seed(83419).parse(argc, argv);

    // Allocate buffer, open files, measure file sizes
    unsigned char* buf = new unsigned char[args.block_size];

    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);

    if ((ssize_t) args.file_size < 0) {
        args.file_size = io61_filesize(inf);
    }
    if ((ssize_t) args.file_size < 0) {
        fprintf(stderr, "reordercat61: can't get size of input file\n");
        exit(1);
    }
    if (io61_seek(inf, 0) < 0) {
        fprintf(stderr, "reordercat61: input file is not seekable\n");
        exit(1);
    }

    io61_file* outf = io61_open_check(args.output_file,
                                      O_WRONLY | O_CREAT | O_TRUNC);
    if (io61_seek(outf, 0) < 0) {
        fprintf(stderr, "reordercat61: output file is not seekable\n");
        exit(1);
    }

    // Calculate random permutation of file's blocks
    size_t nblocks = args.file_size / args.block_size;
    if (nblocks > (30 << 20)) {
        fprintf(stderr, "reordercat61: file too large\n");
        exit(1);
    } else if (nblocks * args.block_size != args.file_size) {
        fprintf(stderr, "reordercat61: input file size not a multiple of block size\n");
        exit(1);
    }
    std::uniform_int_distribution<size_t> blkdistrib(0, nblocks - 1);

    size_t* blockpos = new size_t[nblocks];
    for (size_t i = 0; i < nblocks; ++i) {
        blockpos[i] = i;
    }

    // Copy file data
    while (nblocks != 0) {
        // Choose block to read
        size_t index = blkdistrib(args.engine);
        size_t pos = blockpos[index] * args.block_size;
        blockpos[index] = blockpos[nblocks - 1];
        --nblocks;

        // Transfer that block
        int r = io61_seek(inf, pos);
        assert(r == 0);

        ssize_t nr = io61_read(inf, buf, args.block_size);
        if (nr <= 0) {
            break;
        }

        r = io61_seek(outf, pos);
        assert(r == 0);

        ssize_t nw = io61_write(outf, buf, nr);
        assert(nw == nr);

        args.after_write(outf);
    }

    io61_close(inf);
    io61_close(outf);
    delete[] buf;
    delete[] blockpos;
}
