#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <vector>
#include <algorithm>
// Check that never-allocated memory can be coalesced with freed memory.

int main() {
    constexpr size_t nmax = 2000;
    void* ptrs[nmax];
    size_t n = 0;
    while (n != nmax) {
        ptrs[n] = m61_malloc(850);
        assert(ptrs[n]);
        ++n;
    }
    std::sort(ptrs, ptrs + n);

    std::default_random_engine randomness(std::random_device{}());
    while (n > 1) {
        size_t i = uniform_int(size_t(1), n - 1, randomness);
        m61_free(ptrs[i]);
        ptrs[i] = ptrs[n - 1];
        --n;
    }

    void* bigptr = m61_malloc(7 << 20);
    assert(bigptr);
    m61_free(bigptr);
    m61_free(ptrs[0]);

    m61_print_statistics();
}

//! alloc count: active          0   total       2001   fail          0
//! alloc size:  active        ???   total    9040032   fail          0
