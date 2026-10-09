#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
    const char *path = "/var/lib/lk7-lab/work/inbox";
    if (mkfifo(path, 0640) < 0 && errno != EEXIST) {
        perror("mkfifo");
        return 1;
    }
    /* Linux allows O_RDWR on a FIFO. Open succeeds without an external writer. */
    int fd = open(path, O_RDWR);
    if (fd < 0) {
        perror("open inbox");
        return 1;
    }
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("worker ready; waiting for input");
    for (;;) {
        char data[256];
        ssize_t length = read(fd, data, sizeof(data));
        if (length < 0 && errno == EINTR) continue;
        if (length <= 0) break;
        printf("received: %.*s", (int)length, data);
    }
    close(fd);
    return 0;
}
