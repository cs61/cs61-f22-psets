#include "m61.hh"
#include <cstdio>
// Check total allocation count statistic.

int main() {
    for (int i = 0; i != 10; ++i) {
        (void) m61_malloc(1);
    }
    m61_print_statistics();
}

// In expected output, "???" can match any number of characters.

//! alloc count: active        ???   total         10   fail        ???
//! alloc size:  active        ???   total        ???   fail        ???
