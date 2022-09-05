#include "m61.hh"
#include <cstdio>
#include <cassert>
#include <cinttypes>
// Check failed allocation size statistic.

int main() {
    void* ptrs[10];
    for (int i = 0; i != 10; ++i) {
        ptrs[i] = m61_malloc(i + 1);
    }
    for (int i = 0; i != 5; ++i) {
        m61_free(ptrs[i]);
    }
    size_t very_large_size = SIZE_MAX - 200;
    void* garbage = m61_malloc(very_large_size);
    assert(!garbage);
    m61_print_statistics();
}

// The text within ??{...}?? pairs is a REGULAR EXPRESSION.
// (Some sites about regular expressions:
//  http://www.lornajane.net/posts/2011/simple-regular-expressions-by-example
//  https://www.icewarp.com/support/online_help/203030104.htm
//  http://xkcd.com/208/
// Dig deeper into how regular expresisons are implemented:
//  http://swtch.com/~rsc/regexp/regexp1.html )
// This particular regular expression lets our check work correctly on both
// 32-bit and 64-bit architectures. It checks for a `fail_size` of either
// 2^32 - 201 or 2^64 - 201.

//! ???
//! alloc count: active          5   total         10   fail          1
//! alloc size:  active        ???   total         55   fail ??{4294967095|18446744073709551415}??
