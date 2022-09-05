#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check that invalid free of misaligned data does not cause crash.

int main() {
    void* ptr = m61_malloc(2001);
    fprintf(stderr, "Bad pointer %p\n", (char*) ptr + 127);
    m61_free((char*) ptr + 127);
    m61_print_statistics();
}

//! Bad pointer ??{0x\w+}=ptr??
//! MEMORY BUG: test???.cc:10: invalid free of pointer ??ptr??, not allocated
//! ???
