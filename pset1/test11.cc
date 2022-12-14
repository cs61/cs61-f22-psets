#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
#include <cstdlib>
// Check heap_min and heap_max using m61_allocator.

int main() {
    uintptr_t heap_first = 0;
    uintptr_t heap_last = 0;

    // The `allocator` object allocates arrays of bytes using
    // m61_malloc and m61_free.
    m61_allocator<char> allocator;
    for (int i = 0; i != 100; ++i) {
        size_t sz = rand() % 100;
        char* p = allocator.allocate(sz);
        if (!heap_first || heap_first > (uintptr_t) p) {
            heap_first = (uintptr_t) p;
        }
        if (!heap_last || heap_last < (uintptr_t) p + sz) {
            heap_last = (uintptr_t) p + sz;
        }
        allocator.deallocate(p, sz);
    }

    m61_statistics stat = m61_get_statistics();
    assert(stat.heap_min <= heap_first);
    assert(heap_last - 1 <= stat.heap_max);
}
