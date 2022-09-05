#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check heap_min and heap_max, simple case.

int main() {
    char* p = (char*) m61_malloc(10);

    m61_statistics stat = m61_get_statistics();
    assert((uintptr_t) p >= stat.heap_min);
    assert((uintptr_t) p + 9 <= stat.heap_max);

    m61_free(p);
}
