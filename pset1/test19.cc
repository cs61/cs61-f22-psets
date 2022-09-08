#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
#include <random>
// Check 100 random diabolical m61_calloc arguments.

int main() {
    std::default_random_engine randomness(std::random_device{}());

    void* success = m61_calloc(0x1000, 2);

    for (int i = 0; i != 100; ++i) {
        size_t a = uniform_int(size_t(0), size_t(0x2000000), randomness) * 16;
        size_t b = size_t(-1) / a;
        b += uniform_int(size_t(1), size_t(0x20000000) / a, randomness);
        void* p = m61_calloc(a, b);
        assert(p == nullptr);
    }

    m61_free(success);
    m61_print_statistics();
}

//! alloc count: active          0   total          1   fail        100
//! alloc size:  active        ???   total       8192   fail        ???
