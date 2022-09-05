#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check detection of diabolical wild free.

int main() {
    char* a = (char*) m61_malloc(208);
    char* b = (char*) m61_malloc(50);
    char* c = (char*) m61_malloc(208);
    char* p = (char*) m61_malloc(3000);
    (void) a, (void) c;
    memcpy(p, b - 208, 450);
    m61_free(p + 208);
    m61_print_statistics();
}

//! MEMORY BUG???: invalid free of pointer ???, not allocated
//! ???
