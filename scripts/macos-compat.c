// SPDX-License-Identifier: AGPL-3.0-only
// pipe2 ve dup3, macOS 27 SDK'sında geldi; macOS 26'nın libSystem'inde yok. Homebrew'un statik kütüphaneleri
// (ör. libevent) macOS 27'de derlenince bunları zorunlu sembol olarak ister ve uygulama macOS 26'da açılışta
// "Symbol not found: _pipe2" ile kapanır. Bu dosya libCChiaki.a'ya girer: bağlayıcı sembolleri buradan çözer,
// uygulama libSystem'den istemez. Davranış aynıdır (O_CLOEXEC / O_NONBLOCK bayrakları fcntl ile verilir).
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

static int couchsubs_set_flags(int fd, int flags) {
  if ((flags & O_CLOEXEC) && fcntl(fd, F_SETFD, FD_CLOEXEC) == -1) return -1;
  if (flags & O_NONBLOCK) {
    int fl = fcntl(fd, F_GETFL);
    if (fl == -1 || fcntl(fd, F_SETFL, fl | O_NONBLOCK) == -1) return -1;
  }
  return 0;
}

int pipe2(int fds[2], int flags) {
  if (flags & ~(O_CLOEXEC | O_NONBLOCK)) { errno = EINVAL; return -1; }
  if (pipe(fds) == -1) return -1;
  if (couchsubs_set_flags(fds[0], flags) == -1 || couchsubs_set_flags(fds[1], flags) == -1) {
    int e = errno;
    close(fds[0]);
    close(fds[1]);
    errno = e;
    return -1;
  }
  return 0;
}

int dup3(int oldfd, int newfd, int flags) {
  if ((flags & ~O_CLOEXEC) || oldfd == newfd) { errno = EINVAL; return -1; }
  if (dup2(oldfd, newfd) == -1) return -1;
  if (couchsubs_set_flags(newfd, flags) == -1) {
    int e = errno;
    close(newfd);
    errno = e;
    return -1;
  }
  return 0;
}
