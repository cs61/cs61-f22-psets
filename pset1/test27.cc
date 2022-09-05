#include "m61.hh"
#include <cstdio>
#include <cstring>
#include <deque>
#include <sys/resource.h>
// Check for memory reuse and bounded metadata: up to 100 active allocations.

int main() {
    std::default_random_engine randomness(std::random_device{}());

    // get initial memory usage
    struct rusage ubefore, uafter;
    int r = getrusage(RUSAGE_SELF, &ubefore);
    assert(r >= 0);

    // make at least 50000 20-byte allocations and free them;
    // at most 100 allocations are active at a time
    constexpr int nptrs = 100;
    std::deque<void*> ptrs;
    for (int i = 0; i != 100000; ++i) {
        if (ptrs.size() >= nptrs
            || (ptrs.size() > 0 && uniform_int(0, 2, randomness) == 0)) {
            m61_free(ptrs.front());
            ptrs.pop_front();
        } else {
            void* ptr = m61_malloc(20);
            assert(ptr);
            ptrs.push_back(ptr);
            memset(ptr, i % 256, 10);
        }
    }
    while (!ptrs.empty()) {
        m61_free(ptrs.front());
        ptrs.pop_front();
    }
    m61_print_statistics();

    // report peak memory usage
    r = getrusage(RUSAGE_SELF, &uafter);
    assert(r >= 0);
    if (uafter.ru_maxrss < ubefore.ru_maxrss) {
        printf("memory usage decreased over test?!\n");
    } else {
        size_t kb = uafter.ru_maxrss - ubefore.ru_maxrss;
        size_t denom = 1;
#if __APPLE__
        // Mac OS X reports memory usage in *bytes*, not KB
        denom = 1024;
#endif
        printf("peak memory used: %lukb\n", kb / denom);
    }
}

//!!TIME
//! alloc count: active          0   total ??>=50000??   fail        ???
//! alloc size:  active          0   total ??>=1000000??   fail        ???
//! peak memory used: ??{\d+kb}=peak_memory??
