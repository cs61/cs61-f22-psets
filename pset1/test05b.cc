#include "m61.hh"
#include <cstdio>
// Check total allocation size statistic and allocation non-overlap.

int main() {
    char* ptrs[10];
    for (int i = 0; i != 10; ++i) {
        ptrs[i] = (char*) m61_malloc(i + 1);
        assert(ptrs[i]);
        for (int j = 0; j != i; ++j) {
            assert(ptrs[i] + i <= ptrs[j] || ptrs[j] + j <= ptrs[i]);
        }
    }
    for (int i = 0; i != 5; ++i) {
        m61_free(ptrs[i]);
    }
    m61_print_statistics();
}

//! alloc count: active          5   total         10   fail        ???
//! alloc size:  active        ???   total         55   fail        ???
