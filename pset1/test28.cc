#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <vector>
// Check for memory reuse: 1M allocations, at most one active.

int main() {
    for (int i = 0; i != 1000000; ++i) {
        void* ptr = m61_malloc(1000);
        assert(ptr);
        m61_free(ptr);
    }
    m61_print_statistics();
}

//!!TIME
//! alloc count: active          0   total    1000000   fail          0
//! alloc size:  active        ???   total 1000000000   fail          0
