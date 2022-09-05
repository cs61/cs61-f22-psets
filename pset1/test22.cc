#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <vector>
// Check that freed memory may be immediately reused.

int main() {
    const size_t nmax = 10000;
    void* ptrs[nmax];
    size_t n = 0;
    while (n != nmax) {
        ptrs[n] = m61_malloc(850);
        if (!ptrs[n]) {
            break;
        }
        ++n;
    }

    if (n > 0) {
        m61_free(ptrs[n / 2]);
        ptrs[n / 2] = m61_malloc(850);
        assert(ptrs[n / 2]);
    }

    for (size_t i = 0; i != n; ++i) {
        m61_free(ptrs[i]);
    }
    m61_print_statistics();
}

//! alloc count: active          0   total ??>=8000??   fail  ??{0|1}??
//! alloc size:  active        ???   total ??>=6800000??   fail ??{0|850}??
