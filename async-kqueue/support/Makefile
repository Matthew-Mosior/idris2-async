IDRIS := idris2

TARGET = kqueue-idris
TARGET_VERSION ?= 0.1.0

INSTALLDIR = `${IDRIS} --libdir`/kqueue-${TARGET_VERSION}
LIBDIR = "$(INSTALLDIR)/lib"

LDFLAGS =
CFLAGS = -O2 -g -Wall -Wextra -fPIC

CC_VERSION := $(shell $(CC) --version)
MACHINE := $(shell $(CC) -dumpmachine)

ifneq (,$(findstring cygwin,$(MACHINE)))
	OS := windows
	SHLIB_SUFFIX := .dll
else ifneq (,$(findstring mingw,$(MACHINE)))
	OS := windows
	SHLIB_SUFFIX := .dll
else ifneq (,$(findstring windows,$(MACHINE)))
	OS := windows
	SHLIB_SUFFIX := .dll
else ifneq (,$(findstring darwin,$(MACHINE)))
	OS := darwin
	SHLIB_SUFFIX := .dylib
else ifneq (,$(findstring bsd,$(MACHINE)))
	OS := bsd
	SHLIB_SUFFIX := .so
else
	OS := linux
	SHLIB_SUFFIX := .so
endif

# kqueue is available on macOS and BSD systems.
# No additional library is required: kqueue(2) and kevent(2)
# are provided by the system C library.
ifeq ($(OS),darwin)
	CFLAGS +=
else ifeq ($(OS),bsd)
	CFLAGS +=
else
	$(error kqueue-idris is only supported on macOS and BSD systems)
endif

ifeq ($(findstring clang,$(CC_VERSION)),clang)
	LDFLAGS +=
else
	LDFLAGS += -fuse-ld=lld
endif

SRCS = $(wildcard *.c)
OBJS = $(SRCS:.c=.o)
DEPS = $(OBJS:.o=.d)

all: $(TARGET)$(SHLIB_SUFFIX)

$(TARGET)$(SHLIB_SUFFIX): $(OBJS)
	$(CC) $(CFLAGS) -shared $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

-include $(DEPS)

.PHONY: clean

clean:
	rm -f $(OBJS) $(DEPS) $(TARGET)$(SHLIB_SUFFIX)

.PHONY: cleandep

cleandep: clean

.PHONY: install

install:
	@if ! [ -d $(LIBDIR) ]; then mkdir -p $(LIBDIR); fi
	install $(TARGET)$(SHLIB_SUFFIX) $(LIBDIR)
