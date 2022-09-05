#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check detection of boundary write error of multiple zero bytes.

int main() {
    int* array = (int*) m61_malloc(3); // oops, forgot "* sizeof(int)"
    for (int i = 0; i != 3; ++i) {
        array[i] = 0;
    }
    m61_free(array);
    m61_print_statistics();
}

//! MEMORY BUG???: detected wild write during free of pointer ???
//! ???
