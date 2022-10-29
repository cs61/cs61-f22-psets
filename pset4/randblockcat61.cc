#include "io61.hh"

// Usage: ./randblockcat61 [-b MAXBLOCKSIZE] [-r RANDOMSEED] [FILE]
//    Copies the input FILE to standard output in blocks. Each block has a
//    random size between 1 and MAXBLOCKSIZE (which defaults to 4096).

int main(int argc, char* argv[]) {
    // Parse arguments
    io61_args args = io61_args("b:r:o:i:", 4096).set_seed(83419).parse(argc, argv);

    // Allocate buffer, open files
    unsigned char* buf = new unsigned char[args.block_size];
    std::uniform_int_distribution<size_t> szdistrib(1, args.block_size);

    io61_file* inf = io61_open_check(args.input_file, O_RDONLY);
    io61_file* outf = io61_open_check(args.output_file,
                                      O_WRONLY | O_CREAT | O_TRUNC);

    // Copy file data
    while (true) {
        size_t sz = szdistrib(args.engine);
        ssize_t nr = io61_read(inf, buf, sz);
        if (nr <= 0) {
            break;
        }

        ssize_t nw = io61_write(outf, buf, nr);
        assert(nw == nr);

        args.after_write(outf);
    }

    io61_close(inf);
    io61_close(outf);
    delete[] buf;
}
