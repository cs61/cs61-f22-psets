#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check detection of boundary write errors before allocation.

int main() {
    int* ptr = (int*) m61_malloc(sizeof(int) * 10);
    fprintf(stderr, "Will free %p\n", ptr);
    for (int i = 0; i <= 10 /* Whoops! Should be < */; ++i) {
        ptr[i] = i;
    }
    m61_free(ptr);
    m61_print_statistics();
}

//! Will free ??{0x\w+}=ptr??
//! MEMORY BUG???: detected wild write during free of pointer ??ptr??
//! ???
