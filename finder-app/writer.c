#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <syslog.h>
#include <errno.h>

// Receive and accept 2 arguments: file path and string to write
// Write string into the file
// LOG_DEBUG: Writing <string> to <file>
// LOG_ERR:   unexpected errors

int main(int argc, char *argv[])
{
    const char *filepath;
    const char *writestr;
    int fd;
    ssize_t bytes_written;
    size_t len;

    openlog("writer", 0, LOG_USER);

    if (argc != 3) {
        syslog(LOG_ERR, "Invalid number arguments: expected 2, got %d", argc - 1);
        fprintf(stderr, "Usage: %s <file> <string>\n", argv[0]);
        closelog();
        return 1;
    }

    filepath = argv[1];
    writestr = argv[2];
    len = strlen(writestr);

    syslog(LOG_DEBUG, "Writing %s to %s", writestr, filepath);

    fd = open(filepath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd == -1) {
        syslog(LOG_ERR, "open failed for %s: %s", filepath, strerror(errno));
        closelog();
        return 1;
    }

    bytes_written = write(fd, writestr, len);
    if (bytes_written == -1) {
        syslog(LOG_ERR, "write failed for %s: %s", filepath, strerror(errno));
        close(fd);
        closelog();
        return 1;
    }

    if ((size_t)bytes_written != len) {
        syslog(LOG_ERR, "partial write to %s: expected %zu bytes, wrote %zd bytes",
               filepath, len, bytes_written);
        close(fd);
        closelog();
        return 1;
    }

    if (close(fd) == -1) {
        syslog(LOG_ERR, "close failed for %s: %s", filepath, strerror(errno));
        closelog();
        return 1;
    }

    closelog();
    return 0;
}
