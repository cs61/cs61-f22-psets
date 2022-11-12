# compiler flags
CFLAGS := -std=gnu2x -Wall -Wextra -Wshadow -g $(DEFS) $(CFLAGS)
CXXFLAGS := -std=gnu++2a -Wall -Wextra -Wshadow -g $(DEFS) $(CXXFLAGS)

O ?= -O3
ifeq ($(filter 0 1 2 3 s z g fast,$(O)),$(strip $(O)))
override O := -O$(O)
endif

# skip x86 versions in ARM Docker
X86 ?= 0
ifneq ($(X86),1)
 ifneq ($(findstring /usr/x86_64-linux-gnu/bin:,$(PATH)),)
PATH := $(subst /usr/x86_64-linux-gnu/bin:,,$(PATH))
 endif
endif

# sanitizer arguments
ifndef SAN
SAN := $(SANITIZE)
endif
ifeq ($(SAN),1)
 ifndef ASAN
ASAN := $(if $(strip $(shell $(CC) -v 2>&1 | grep 'build=aarch.*target=x86')),,1)
 endif
endif
ifndef TSAN
 ifeq ($(WANT_TSAN),1)
TSAN := $(SAN)
 endif
endif

check_for_sanitizer = $(if $(strip $(shell $(CC) -fsanitize=$(1) -x c -E /dev/null 2>&1 | grep sanitize=)),$(info ** WARNING: The `$(CC)` compiler does not support `-fsanitize=$(1)`.),1)
ifeq ($(TSAN),1)
 ifeq ($(call check_for_sanitizer,thread),1)
CFLAGS += -fsanitize=thread
CXXFLAGS += -fsanitize=thread
 endif
else
 ifeq ($(or $(ASAN),$(LSAN),$(LEAKSAN)),1)
  ifeq ($(call check_for_sanitizer,address),1)
CFLAGS += -fsanitize=address
CXXFLAGS += -fsanitize=address
  endif
 endif
 ifeq ($(or $(LSAN),$(LEAKSAN)),1)
  ifeq ($(call check_for_sanitizer,leak),1)
CFLAGS += -fsanitize=leak
CXXFLAGS += -fsanitize=leak
  endif
 endif
endif
ifeq ($(or $(UBSAN),$(SAN)),1)
 ifeq ($(call check_for_sanitizer,undefined),1)
CFLAGS += -fsanitize=undefined -fno-sanitize-recover=undefined
CXXFLAGS += -fsanitize=undefined -fno-sanitize-recover=undefined
 endif
endif

# profiling
ifeq ($(or $(PROFILE),$(PG)),1)
CFLAGS += -pg
CXXFLAGS += -pg
endif

# NDEBUG
ifeq ($(NDEBUG),1)
CPPFLAGS += -DNDEBUG=1
CFLAGS += -Wno-unused
CXXFLAGS += -Wno-unused
endif

# these rules ensure dependencies are created
DEPCFLAGS = -MD -MF $(DEPSDIR)/$(patsubst %.o,%,$(@F)).d -MP
DEPSDIR := .deps
BUILDSTAMP := $(DEPSDIR)/rebuildstamp
DEPFILES := $(wildcard $(DEPSDIR)/*.d)
ifneq ($(DEPFILES),)
include $(DEPFILES)
endif

# Quiet down make output for stdio and syscall versions.
# If the user runs 'make all' or 'make check', don't provide a separate
# link line for every stdio-% target; instead print 'LINK STDIO VERSIONS'.
ifneq ($(filter all check check-%,$(or $(MAKECMDGOALS),all)),)
DEP_MESSAGES := $(shell mkdir -p $(DEPSDIR); echo LINK STDIO VERSIONS >$(DEPSDIR)/stdio.txt; echo LINK SYSCALL VERSIONS >$(DEPSDIR)/syscall.txt)
STDIO_LINK_LINE = $(shell cat $(DEPSDIR)/stdio.txt)
SYSCALL_LINK_LINE = $(shell cat $(DEPSDIR)/syscall.txt)
else
STDIO_LINK_LINE = LINK $@
SYSCALL_LINK_LINE = LINK $@
endif


# when the C compiler or optimization flags change, rebuild all objects
ifneq ($(strip $(DEP_CC)),$(strip $(CC) $(CPPFLAGS) $(CFLAGS) $(O) X86=$(X86)))
DEP_CC := $(shell mkdir -p $(DEPSDIR); echo >$(BUILDSTAMP); echo "DEP_CC:=$(CC) $(CPPFLAGS) $(CFLAGS) $(O) X86=$(X86)" >$(DEPSDIR)/_cc.d)
endif
ifneq ($(strip $(DEP_CXX)),$(strip $(CXX) $(CPPFLAGS) $(CXXFLAGS) $(O) X86=$(X86) $(LDFLAGS)))
DEP_CXX := $(shell mkdir -p $(DEPSDIR); echo >$(BUILDSTAMP); echo "DEP_CXX:=$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(O) X86=$(X86) $(LDFLAGS)" >$(DEPSDIR)/_cxx.d)
endif


V = 0
ifeq ($(V),1)
run = $(1) $(3)
xrun = /bin/echo "$(1) $(3)" && $(1) $(3)
else
run = @$(if $(2),/bin/echo "  $(2) $(3)" &&,) $(1) $(3)
xrun = $(if $(2),/bin/echo "  $(2) $(3)" &&,) $(1) $(3)
endif
runquiet = @$(1) $(3)

CXX_LINK_PREREQUISITES = $(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) -o $@ $^


PERCENT := %

# cancel implicit rules we don't want
%: %.c
%.o: %.c
%: %.cc
%.o: %.cc
%: %.o
%.o: %.s

$(BUILDSTAMP):
	@mkdir -p $(@D)
	@echo >$@

always:
	@:

clean-hook:
	@:

.PHONY: always clean-hook
.PRECIOUS: %.o
