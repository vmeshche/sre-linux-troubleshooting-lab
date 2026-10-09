#include <stdint.h>
#include <stdio.h>
#include <time.h>

static volatile uint64_t result;

__attribute__((noinline)) uint64_t mix_numbers(uint64_t value) {
    for (unsigned int i = 0; i < 1000000; ++i) {
        value ^= value << 13;
        value ^= value >> 7;
        value ^= value << 17;
    }
    return value;
}

__attribute__((noinline)) void process_batch(void) {
    result = mix_numbers(result + 1);
}

int main(void) {
    struct timespec started, now;
    clock_gettime(CLOCK_MONOTONIC, &started);
    puts("CPU worker started; exit automatically after 15 minutes");
    fflush(stdout);
    do {
        process_batch();
        clock_gettime(CLOCK_MONOTONIC, &now);
    } while (now.tv_sec - started.tv_sec < 900);
    return 0;
}
