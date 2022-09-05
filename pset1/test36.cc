#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check that double free is detected after several valid frees.

int main() {
    constexpr int nptrs = 10;
    void* ptrs[nptrs];
    for (int i = 0; i != nptrs; ++i) {
        ptrs[i] = m61_malloc(10);
    }
    fprintf(stderr, "Will free %p\n", ptrs[2]);
    for (int i = 0; i != nptrs; ++i) {
        m61_free(ptrs[i]);
    }
    ptrs[0] = m61_malloc(20);
    ptrs[1] = m61_malloc(30);
    m61_free(ptrs[2]);
    m61_print_statistics();
}

//! Will free ??{0x\w+}=ptr??
//! MEMORY BUG???: invalid free of pointer ??ptr??, double free
//! ???
