#include "m61.hh"
#include <cstdio>
// Check active allocation count statistic.

int main() {
    void* ptrs[10];
    for (int i = 0; i != 10; ++i) {
        ptrs[i] = m61_malloc(i + 1);
    }
    for (int i = 0; i != 5; ++i) {
        m61_free(ptrs[i]);
    }
    m61_print_statistics();
}

//! alloc count: active          5   total         10   fail        ???
//! alloc size:  active        ???   total        ???   fail        ???
