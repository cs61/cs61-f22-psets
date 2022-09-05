#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check double free detection.

int main() {
    void* ptr = m61_malloc(2001);
    fprintf(stderr, "Will free %p\n", ptr);
    m61_free(ptr);
    m61_free(ptr);
    m61_print_statistics();
}

//! Will free ??{0x\w+}=ptr??
//! MEMORY BUG???: invalid free of pointer ??ptr??, double free
//! ???
