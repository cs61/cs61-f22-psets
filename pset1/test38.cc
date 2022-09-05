#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check invalid free of wild heap pointer.

int main() {
    void* ptr1 = m61_malloc(1020);
    void* ptr2 = m61_malloc(2308);
    void* ptr3 = m61_malloc(6161);
    fprintf(stderr, "Bad pointer %p\n", (char*) ptr2 + 64);
    m61_free(ptr1);
    m61_free((char*) ptr2 + 64);
    m61_free(ptr2);
    m61_free(ptr3);
    m61_print_statistics();
}

//! Bad pointer ??{0x\w+}=ptr??
//! MEMORY BUG???: invalid free of pointer ??ptr??, not allocated
//! ???
