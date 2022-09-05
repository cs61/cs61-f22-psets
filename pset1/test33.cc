#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check invalid free of non-heap pointer with active allocations.

int main() {
    void* ptrs[10];
    for (int i = 0; i != 10; ++i) {
        ptrs[i] = m61_malloc(i + 1);
    }
    for (int i = 0; i != 4; ++i) {
        m61_free(ptrs[i]);
    }
    m61_free((void*) 16);
    m61_free(ptrs[4]);
    m61_print_statistics();
}

//! MEMORY BUG???: invalid free of pointer ???, not in heap
//! ???
