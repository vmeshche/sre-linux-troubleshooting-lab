#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t reopen_requested = 0;
static void request_reopen(int signal_number) {
    (void)signal_number;
    reopen_requested = 1;
}

static int write_all(int fd, const char *data, size_t length) {
    while (length) {
        ssize_t count = write(fd, data, length);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return -1;
        data += count;
        length -= (size_t)count;
    }
    return 0;
}

int main(void) {
    const char *path = "/var/lib/lk7-lab/log/demo.log";
    struct sigaction action = {0};
    action.sa_handler = request_reopen;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGUSR1, &action, NULL) < 0) return 1;
    /* Block SIGUSR1 except while waiting: avoids a check/pause race. */
    sigset_t blocked, previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGUSR1);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous) < 0) return 1;
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0640);
    if (fd < 0) { perror("open log"); return 1; }
    char block[4096];
    memset(block, 'x', sizeof(block));
    for (int i = 0; i < 4096; ++i) {
        if (write_all(fd, block, sizeof(block)) < 0) {
            perror("write log"); close(fd); return 1;
        }
    }
    if (fsync(fd) < 0) { perror("fsync"); close(fd); return 1; }
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("16 MiB written; keeping the log descriptor open");
    for (;;) {
        while (!reopen_requested) sigsuspend(&previous);
        reopen_requested = 0;
        close(fd);
        fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0640);
        if (fd < 0) { perror("reopen log"); return 1; }
        const char message[] = "log reopened after SIGUSR1\n";
        if (write_all(fd, message, sizeof(message) - 1) < 0) return 1;
        puts("log reopened; old descriptor closed");
    }
}
