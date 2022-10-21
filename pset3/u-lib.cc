#include "u-lib.hh"

// panic, assert_fail
//     Call the SYSCALL_PANIC system call so the kernel loops until Control-C.

void panic(const char* format, ...) {
    va_list val;
    va_start(val, format);
    char buf[240];
    int len = vsnprintf(buf, sizeof(buf) - 1, format, val);
    va_end(val);
    if (len > 0 && buf[len - 1] != '\n') {
        strcpy(buf + len - (len == (int) sizeof(buf) - 1), "\n");
    }
    sys_panic(buf);
}

int error_vprintf(int cpos, int color, const char* format, va_list val) {
    return console_vprintf(cpos, color, format, val);
}

void assert_fail(const char* file, int line, const char* msg,
                 const char* description) {
    cursorpos = CPOS(23, 0);
    char buf[240];
    if (description) {
        snprintf(buf, sizeof(buf),
                 "%s:%d: %s\n%s:%d: user assertion '%s' failed\n",
                 file, line, description, file, line, msg);
    } else {
        snprintf(buf, sizeof(buf),
                 "%s:%d: user assertion '%s' failed\n",
                 file, line, msg);
    }
    sys_panic(buf);
}
