#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
#include <cstdlib>
// Check that heap_min and heap_max do not overlap stack or globals.

static int global;

int main() {
    for (int i = 0; i != 100; ++i) {
        size_t sz = rand() % 100;
        char* p = (char*) m61_malloc(sz);
        m61_free(p);
    }
    m61_statistics stat = m61_get_statistics();

    union {
        uintptr_t addr;
        int* iptr;
        m61_statistics* statptr;
        int (*mainptr)();
    } x;
    x.iptr = &global;
    assert(x.addr + sizeof(int) < stat.heap_min || x.addr >= stat.heap_max);
    x.statptr = &stat;
    assert(x.addr + sizeof(int) < stat.heap_min || x.addr >= stat.heap_max);
    x.mainptr = &main;
    assert(x.addr + sizeof(int) < stat.heap_min || x.addr >= stat.heap_max);
}
