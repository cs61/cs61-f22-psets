#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <vector>
// Check that large blocks of memory can be split into smaller pieces.

int main() {
    void* bigptr = m61_malloc(7 << 20);
    assert(bigptr);

    void* smallptr = m61_malloc(1000);
    assert(smallptr);

    // addresses do not overlap
    uintptr_t bigaddr = reinterpret_cast<uintptr_t>(bigptr);
    uintptr_t smalladdr = reinterpret_cast<uintptr_t>(smallptr);
    assert(bigaddr + (7 << 20) <= smalladdr || smalladdr + 1000 <= bigaddr);

    m61_free(bigptr);

    const size_t nmax = 7168;
    void* ptrs[nmax];
    size_t n = 0;
    while (n != nmax) {
        ptrs[n] = m61_malloc(850);
        assert(ptrs[n]);
        ++n;
    }

    for (size_t i = 0; i != n; ++i) {
        m61_free(ptrs[i]);
    }
    m61_free(smallptr);

    m61_print_statistics();
}

//! alloc count: active          0   total       7170   fail          0
//! alloc size:  active        ???   total ??>=6800000??   fail ??{0|850}??
