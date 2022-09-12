#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
#include <algorithm>
// Check that double free is detected after more frees and allocations.

int main() {
    constexpr int nptrs = 13;
    void* ptrs[nptrs];
    for (int i = 0; i != nptrs; ++i) {
        ptrs[i] = m61_malloc(10);
    }
    std::sort(ptrs, ptrs + nptrs);
    fprintf(stderr, "Will double free %p\n", ptrs[2]);
    for (int i = 0; i < nptrs; i += 2) {
        m61_free(ptrs[i]);
    }
    ptrs[0] = m61_malloc(1000);
    ptrs[4] = m61_malloc(2000);
    m61_free(ptrs[2]);
    m61_print_statistics();
}

//! Will double free ??{0x\w+}=ptr??
//! MEMORY BUG???: invalid free of pointer ??ptr??, double free
//! ???
