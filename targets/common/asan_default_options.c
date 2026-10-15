/* Linked into the libFuzzer-style .asan targets: no leak reports (they would bury the real crash),
   via ASan's defaults hook, with a preinit fallback for a shared ASan runtime. */
#include <stdlib.h>

const char *__asan_default_options(void) {
    return "detect_leaks=0";
}

const char *__lsan_default_options(void) {
    return "detect_leaks=0";
}

static void asan_disable_leaks(void) {
    const char *old = getenv("ASAN_OPTIONS");
    if (!old || !*old) {
        setenv("ASAN_OPTIONS", "detect_leaks=0", 1);
    }
}
__attribute__((section(".preinit_array"), used))
static void (*asan_disable_leaks_preinit)(void) = asan_disable_leaks;
