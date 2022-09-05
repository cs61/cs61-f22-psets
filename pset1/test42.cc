#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cstring>
// Check that a correct execution does not report errors.

int main() {
    for (int i = 0; i != 10; ++i) {
        int* ptr = (int*) m61_malloc(10 * sizeof(int));
        for (int j = 0; j != 10; ++j) {
            ptr[i] = i;
        }
        m61_free(ptr);
    }
    m61_print_statistics();
}

//! alloc count: active          0   total         10   fail          0
//! alloc size:  active          0   total        400   fail          0
