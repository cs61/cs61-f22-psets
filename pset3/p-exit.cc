#include "u-lib.hh"
#ifndef ALLOC_SLOWDOWN
#define ALLOC_SLOWDOWN 18
#endif

extern uint8_t end[];

uint8_t* heap_top;
uint8_t* stack_bottom;

// Remember which pages we wrote data into
unsigned char pagemark[4096] = {0};

void process_main() {
    for (size_t i = 0; i != sizeof(pagemark); ++i) {
        assert(pagemark[i] == 0);
    }

    while (true) {
        int x = rand(0, ALLOC_SLOWDOWN);
        if (x == 0) {
            // fork, then either exit or start allocating
            pid_t p = sys_fork();
            int choice = rand(0, 2);
            if (choice == 0 && p > 0) {
                sys_exit();
            } else if (choice != 2 ? p > 0 : p == 0) {
                break;
            }
        } else {
            sys_yield();
        }
    }

    int speed = rand(1, 16);
    pid_t self = sys_getpid();

    uint8_t* heap_bottom = (uint8_t*) round_up((uintptr_t) end, PAGESIZE);
    heap_top = heap_bottom;
    stack_bottom = (uint8_t*) round_down((uintptr_t) rdrsp() - 1, PAGESIZE);
    unsigned nalloc = 0;

    // Allocate heap pages until out of address space,
    // forking along the way.
    while (heap_top != stack_bottom) {
        int x = rand(0, 6 * ALLOC_SLOWDOWN);
        if (x >= 8 * speed) {
            if (x % 4 < 2 && heap_top != heap_bottom) {
                unsigned pn = rand(0, (heap_top - heap_bottom - 1) / PAGESIZE);
                if (pn < sizeof(pagemark)) {
                    volatile uint8_t* addr = heap_bottom + pn * PAGESIZE;
                    assert(*addr == pagemark[pn]);
                    *addr = pagemark[pn] = self;
                    assert(*addr == self);
                }
            }
            sys_yield();
            continue;
        }

        x = rand(0, 7 + min(nalloc / 4, 10U));
        if (x < 2) {
            if (sys_fork() == 0) {
                pid_t new_self = sys_getpid();
                assert(new_self != self);
                self = new_self;
                speed = rand(1, 16);
            }
        } else if (x < 3) {
            sys_exit();
        } else if (sys_page_alloc(heap_top) >= 0) {
            // check that the page starts out all zero
            for (unsigned long* l = (unsigned long*) heap_top;
                 l != (unsigned long*) (heap_top + PAGESIZE);
                 ++l) {
                assert(*l == 0);
            }
            // check we can write to new page
            *heap_top = speed;
            // check we can write to console
            console[CPOS(24, 79)] = speed;
            // record data written
            unsigned pn = (heap_top - heap_bottom) / PAGESIZE;
            if (pn < sizeof(pagemark)) {
                pagemark[pn] = speed;
            }
            // update `heap_top`
            heap_top += PAGESIZE;
            nalloc = (heap_top - heap_bottom) / PAGESIZE;
            // clear "Out of physical memory" msg
            if (console[CPOS(24, 0)]) {
                console_printf(CPOS(24, 0), 0, "\n");
            }
        } else if (nalloc < 4) {
            sys_exit();
        } else {
            nalloc -= 4;
        }
    }

    // After running out of memory
    while (true) {
        if (rand(0, 2 * ALLOC_SLOWDOWN - 1) == 0) {
            sys_exit();
        } else {
            sys_yield();
        }
    }
}
