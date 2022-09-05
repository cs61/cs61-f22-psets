#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <vector>
// Check for memory reuse: 5M allocations, at most 5 active.

int main() {
    for (int i = 0; i != 1000000; ++i) {
        void* ptrs[5];
        for (int j = 0; j != 5; ++j) {
            ptrs[j] = m61_malloc(1000);
            assert(ptrs[j]);
        }
        for (int j = 5; j != 0; --j) {
            m61_free(ptrs[j - 1]);
        }
    }
    m61_print_statistics();
}

//!!TIME
//! alloc count: active          0   total    5000000   fail          0
//! alloc size:  active        ???   total 5000000000   fail          0
