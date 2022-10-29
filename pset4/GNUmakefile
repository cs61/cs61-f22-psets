TESTS := $(patsubst %.cc,%,$(filter-out singleslot-% slow-% stdio-% syscall-% io61.cc,$(wildcard *61.cc)))
STDIOTESTS = $(patsubst %,stdio-%,$(TESTS))
SLOWTESTS = $(patsubst %,slow-%,$(TESTS))
SYSCALLTESTS = $(patsubst %,syscall-%,$(TESTS))
all: tests socketpipe

# Default optimization level
O ?= 2
-include build/rules.mk

%.o: %.cc $(BUILDSTAMP)
	$(call run,$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(DEPCFLAGS) $(O) -o $@ -c,COMPILE,$<)

$(TESTS): %: io61.o helpers.o %.o
	$(call run,$(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) -o $@ $^ $(LIBS),LINK $@)

slow-io61.o: slow-io61.cc
$(SLOWTESTS): slow-%: slow-io61.o helpers.o %.o
	$(call run,$(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) -o $@ $^ $(LIBS),LINK $@)

stdio-io61.o: stdio-io61.cc
$(STDIOTESTS): stdio-%: stdio-io61.o helpers.o %.o
	$(call run,$(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) -o $@ $^ $(LIBS),$(STDIO_LINK_LINE))
	@echo >$(DEPSDIR)/stdio.txt

syscall-io61.o: syscall-io61.cc
$(SYSCALLTESTS): syscall-%: syscall-io61.o helpers.o %.o
	$(call run,$(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) -o $@ $^ $(LIBS),$(SYSCALL_LINK_LINE))
	@echo >$(DEPSDIR)/syscall.txt

socketpipe: socketpipe.o
	$(call run,$(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) -o $@ $^ $(LIBS),LINK $@)


all:
	@echo "*** Run 'make check' to check your work."

tests: $(TESTS)
stdio: $(STDIOTESTS)
slow: $(SLOWTESTS)

check:
	perl check.pl

check-%:
	perl check.pl $(subst check-,,$@)

clean: clean-main
clean-main:
	$(call run,rm -f $(TESTS) $(SLOWTESTS) $(STDIOTESTS) $(SYSCALLTESTS) socketpipe *.o core *.core,CLEAN)
	$(call run,rm -rf $(DEPSDIR) files *.dSYM)

distclean: clean

.PRECIOUS: %.o
.PHONY: all clean clean-main clean-hook distclean \
	tests stdio slow check check-% prepare-check
export STRACE NOSTDIO TRIALS MAXTIME TMP V
