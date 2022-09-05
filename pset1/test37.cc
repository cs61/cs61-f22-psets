#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check invalid free of wild heap pointer.

int main() {
    void* ptr = m61_malloc(2001);
    fprintf(stderr, "Bad pointer %p\n", (char*) ptr + 128);
    m61_free((char*) ptr + 128);
    m61_print_statistics();
}

//! Bad pointer ??{0x\w+}=ptr??
//! MEMORY BUG???: invalid free of pointer ??ptr??, not allocated
//! ???
