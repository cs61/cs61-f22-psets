#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <vector>
#include <algorithm>
// Check that small blocks of memory can be coalesced into larger pieces.

int main() {
    const size_t nmax = 7168;
    void* ptrs[nmax];
    size_t n = 0;
    while (n != nmax) {
        ptrs[n] = m61_malloc(850);
        assert(ptrs[n]);
        ++n;
    }
    // ensure smallest address is in `ptrs[0]`
    std::sort(ptrs, ptrs + n);

    std::default_random_engine randomness(std::random_device{}());
    while (n != 1) {
        size_t i = uniform_int(size_t(1), n - 1, randomness);
        m61_free(ptrs[i]);
        ptrs[i] = ptrs[n - 1];
        --n;
    }

    void* bigptr = m61_malloc(6091950);
    assert(bigptr);
    m61_free(bigptr);

    m61_statistics stat = m61_get_statistics();
    assert(reinterpret_cast<uintptr_t>(bigptr) >= stat.heap_min);
    assert(reinterpret_cast<uintptr_t>(bigptr) + 6091949 <= stat.heap_max);

    m61_print_statistics();
}

//! alloc count: active          1   total       7169   fail          0
//! alloc size:  active        ???   total   12184750   fail          0
