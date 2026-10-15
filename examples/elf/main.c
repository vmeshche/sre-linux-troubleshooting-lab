#include <stdio.h>
#include "calculate.h"

int initialized = 7;
int zero_initialized;
const char greeting[] = "hello from ELF";

int main(void) {
    zero_initialized = calculate(initialized);
    printf("%s: %d\n", greeting, zero_initialized);
    return 0;
}
