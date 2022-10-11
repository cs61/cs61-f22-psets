#include "u-lib.hh"
#ifndef ALLOC_SLOWDOWN
#define ALLOC_SLOWDOWN 100
#endif

extern uint8_t end[];

uint8_t* heap_top;
uint8_t* stack_bottom;

// Ensure kernel can load multi-page programs by including some big objects.
struct test_struct {
    int field1;
    unsigned char buf[4096];
    int field2;
};
const test_struct test1 = {61, {0}, 6161};
test_struct test2;

void process_main() {
    pid_t initial_pid = sys_getpid();
    test2.field1 = 61;
    assert(test1.field1 == 61 && test1.field2 == 6161);

    // Fork a total of three new copies, checking `fork` return values.
    pid_t p1 = sys_fork();
    pid_t intermediate_pid = sys_getpid();
    if (p1 == 0) {
        assert(intermediate_pid != initial_pid);
    } else {
        assert(intermediate_pid == initial_pid && p1 != initial_pid);
    }

    pid_t p2 = sys_fork();
    pid_t final_pid = sys_getpid();
    if (p2 == 0) {
        assert(final_pid != initial_pid && final_pid != intermediate_pid);
    } else {
        assert(p2 != p1 && p2 != intermediate_pid && p2 != initial_pid);
        assert(final_pid == intermediate_pid);
    }

    // Check that multi-page segments can be loaded.
    assert(test1.field1 == 61 && test1.field2 == 6161);
    assert(test2.field1 == 61);
    test2.field2 = 61 + final_pid;
    sys_yield();
    assert(test2.field2 == 61 + final_pid);

    // The rest of this code is like p-allocator.c.

    pid_t p = sys_getpid();
    srand(p);

    uint8_t* heap_bottom = (uint8_t*) round_up((uintptr_t) end, PAGESIZE);
    heap_top = heap_bottom;
    stack_bottom = (uint8_t*) round_down((uintptr_t) rdrsp() - 1, PAGESIZE);

    while (heap_top != stack_bottom) {
        int x = rand(0, ALLOC_SLOWDOWN - 1);
        if (x < p) {
            if (sys_page_alloc(heap_top) < 0) {
                break;
            }
            // check that the page starts out all zero
            for (unsigned long* l = (unsigned long*) heap_top;
                 l != (unsigned long*) (heap_top + PAGESIZE);
                 ++l) {
                assert(*l == 0);
            }
            // check we can write to new page
            *heap_top = p;
            // check we can write to console
            console[CPOS(24, 79)] = p;
            // update `heap_top`
            heap_top += PAGESIZE;
        } else if (x < p + 1 && heap_bottom < heap_top) {
            // ensure we can write to any previously-allocated page
            uintptr_t addr = rand((uintptr_t) heap_bottom,
                                  (uintptr_t) heap_top - 1);
            *((char*) addr) = p;
        }
        sys_yield();
    }

    // After running out of memory, do nothing forever
    while (true) {
        sys_yield();
    }
}
