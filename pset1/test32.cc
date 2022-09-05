#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check invalid free of non-heap pointer near heap region.

int main() {
    char* ptr = (char*) m61_malloc(32);
    m61_free(ptr - 32);
    m61_print_statistics();
}

//! MEMORY BUG???: invalid free of pointer ???, not in heap
//! ???
