#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check invalid free of stack pointer.

int main() {
    int x;
    m61_free(&x);
    m61_print_statistics();
}

//! MEMORY BUG???: invalid free of pointer ???, not in heap
//! ???
