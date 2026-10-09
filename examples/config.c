#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
    int fd = open("/etc/lk7-lab/app.conf", O_RDONLY);
    if (fd < 0) {
        perror("startup failed");
        return 1;
    }
    char data[256];
    ssize_t length = read(fd, data, sizeof(data) - 1);
    if (length < 0) {
        perror("read failed");
        close(fd);
        return 1;
    }
    data[length] = '\0';
    close(fd);
    printf("config loaded: %s", data);
    return 0;
}
