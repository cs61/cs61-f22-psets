#include "m61.hh"
#include <cstdio>
#include <cstring>
// Check total allocation size statistic and contents preservation.

const char* const contents[10] = {
    "",
    "M",
    "ar",
    "ria",
    "ge, ",
    "by Ma",
    "rianne",
    " Moore.",
    " This in",
    "stitution"
};

void check_pointers(char** ptrs) {
    for (int i = 0; i != 10; ++i) {
        if (ptrs[i]) {
            assert(memcmp(ptrs[i], contents[i], i) == 0);
            for (int j = 0; j != 10; ++j) {
                if (i != j && ptrs[j]) {
                    assert(ptrs[i] + i <= ptrs[j] || ptrs[j] + j <= ptrs[i]);
                }
            }
        }
    }
}

int main() {
    char* ptrs[10];
    for (int i = 0; i != 10; ++i) {
        ptrs[i] = nullptr;
    }
    for (int i = 0; i != 10; ++i) {
        ptrs[i] = (char*) m61_malloc(i + 1);
        assert(ptrs[i]);
        memcpy(ptrs[i], contents[i], i);
        check_pointers(ptrs);
    }
    for (int i = 0; i != 5; ++i) {
        m61_free(ptrs[i]);
        ptrs[i] = nullptr;
        check_pointers(ptrs);
    }
    m61_print_statistics();
}

//! alloc count: active          5   total         10   fail        ???
//! alloc size:  active        ???   total         55   fail        ???
