#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check that invalid free inside allocated block reports containing block.

int main() {
    void* ptr1 = m61_malloc(1020);
    void* ptr2 = m61_malloc(2308);
    void* ptr3 = m61_malloc(6161);
    m61_free((char*) ptr2 + 64);
    m61_free(ptr1);
    m61_free(ptr2);
    m61_free(ptr3);
    m61_print_statistics();
}

//! MEMORY BUG: test???.cc:11: invalid free of pointer ???, not allocated
//!   test???.cc:9: ??? is 64 bytes inside a 2308 byte region allocated here
//! ???
