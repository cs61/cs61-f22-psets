#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check that null pointers can be freed.

int main() {
    void* p = m61_malloc(10);
    m61_free(nullptr);
    m61_free(p);
    m61_print_statistics();
}

//! alloc count: active          0   total          1   fail          0
//! alloc size:  active        ???   total         10   fail          0
