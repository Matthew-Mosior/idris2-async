// Copyright 2026 Matthew Mosior

#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/stat.h>

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <unistd.h>

int16_t kp_evfilt_read(void)
{
    return EVFILT_READ;
}

int16_t kp_evfilt_write(void)
{
    return EVFILT_WRITE;
}

int16_t kp_evfilt_signal(void)
{
    return EVFILT_SIGNAL;
}

int16_t kp_evfilt_timer(void)
{
    return EVFILT_TIMER;
}

int16_t kp_evfilt_user(void)
{
    return EVFILT_USER;
}

uint16_t kp_ev_add(void)
{
    return EV_ADD;
}

uint16_t kp_ev_delete(void)
{
    return EV_DELETE;
}

uint16_t kp_ev_enable(void)
{
    return EV_ENABLE;
}

uint16_t kp_ev_disable(void)
{
    return EV_DISABLE;
}

uint16_t kp_ev_clear(void)
{
    return EV_CLEAR;
}

uint16_t kp_ev_oneshot(void)
{
    return EV_ONESHOT;
}

uint16_t kp_ev_error(void)
{
    return EV_ERROR;
}

uint16_t kp_ev_eof(void)
{
    return EV_EOF;
}

int kp_kqueue_create(void)
{
    int kq = kqueue();

    if (kq < 0) {
        return -errno;
    }

    if (fcntl(kq, F_SETFD, FD_CLOEXEC) < 0) {
        int err = errno;
        close(kq);
        return -err;
    }

    return kq;
}

int kp_kqueue_close(uint32_t kq)
{
    int r = close((int)kq);

    if (r < 0) {
        return -errno;
    }

    return r;
}

int kp_kevent_ctl(
    uint32_t kq,
    uint64_t ident,
    int16_t filter,
    uint16_t flags)
{
    struct kevent change;

    EV_SET(
        &change,
        ident,
        filter,
        flags,
        0,
        0,
        NULL
    );

    int r = kevent(
        (int)kq,
        &change,
        1,
        NULL,
        0,
        NULL
    );

    if (r < 0) {
        return -errno;
    }

    return r;
}

int kp_kevent_wait(
    uint32_t kq,
    struct kevent *events,
    uint32_t nevents,
    const struct timespec *timeout)
{
    int r = kevent(
        (int)kq,
        NULL,
        0,
        events,
        (int)nevents,
        timeout
    );

    if (r < 0) {
        return -errno;
    }

    return r;
}

uint64_t kp_get_kevent_ident(const struct kevent *ev)
{
    return (uint64_t)ev->ident;
}

int16_t kp_get_kevent_filter(const struct kevent *ev)
{
    return ev->filter;
}

uint16_t kp_get_kevent_flags(const struct kevent *ev)
{
    return ev->flags;
}

uint32_t kp_get_kevent_fflags(const struct kevent *ev)
{
    return ev->fflags;
}

int64_t kp_get_kevent_data(const struct kevent *ev)
{
    return (int64_t)ev->data;
}

uint32_t kp_kevent_size(void)
{
    return (uint32_t)sizeof(struct kevent);
}
