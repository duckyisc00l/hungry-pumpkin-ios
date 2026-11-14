#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// Runs as soon as the app's code is loaded. If this line is missing from
// the log file, the app crashed while iOS was loading it.
__attribute__((constructor)) static void hp_startup_log(void) {
    const char *home = getenv("HOME");
    if (!home) return;
    char path[1024];
    snprintf(path, sizeof(path), "%s/Documents/HungryPumpkin-log.txt", home);
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%ld app code loaded\n", (long)time(NULL));
    fclose(f);
}
