#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <vector>
// Check for memory reuse: at most one active allocation.

int main() {
    for (int i = 0; i != 10000; ++i) {
        void* ptr = m61_malloc(1000);
        assert(ptr);
        m61_free(ptr);
    }
    m61_print_statistics();
}

//! alloc count: active          0   total      10000   fail          0
//! alloc size:  active        ???   total   10000000   fail          0
