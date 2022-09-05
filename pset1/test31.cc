#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check invalid free of non-heap pointer.

int main() {
    m61_free((void*) 16);
    m61_print_statistics();
}

//! MEMORY BUG???: invalid free of pointer ???, not in heap
//! ???
