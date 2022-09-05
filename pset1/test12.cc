#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check that m61_calloc zeroes the returned allocation.

const char data[10] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

int main() {
    char* p = (char*) m61_malloc(10);
    assert(p != nullptr);
    memset(p, 255, 10);
    m61_free(p);

    p = (char*) m61_calloc(10, 1);
    assert(p != nullptr);
    assert(memcmp(data, p, 10) == 0);
    m61_print_statistics();
}

//! alloc count: active          1   total          2   fail          0
//! alloc size:  active        ???   total         20   fail          0
