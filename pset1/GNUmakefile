TESTS = $(patsubst %.cc,%,$(sort $(wildcard test[0-9][0-9].cc test[0-9][0-9][0-9a-z].cc test[0-9][0-9][0-9][a-z].cc)))
all: $(TESTS)

-include build/rules.mk
LIBS = -lm

%.o: %.cc $(BUILDSTAMP)
	$(call run,$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(DEPCFLAGS) $(O) -o $@ -c,COMPILE,$<)

all:
	@echo '*** Run `make check` or `make check-all` to check your work.' 1>&2

test%: m61.o hexdump.o test%.o
	$(call run,$(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) -o $@ $^ $(LIBS),LINK $@)

check:
	@perl check.pl -m $(TESTS)

check-all:
	@perl check.pl -m -k $(TESTS)

check-%:
	@perl check.pl -m "$*"

run-:
	@echo "*** No such test" 1>&2; exit 1

run-%: %
	@test -d out || mkdir out
	@perl check.pl -x $<

testsummary:
	@for t in $(TESTS); do grep -m 1 '^//' $$t.cc | sed 's/^\/\/ */'$$t' /'; done

clean: clean-main
clean-main:
	$(call run,rm -f $(TESTS) hhtest *.o core *.core,CLEAN)
	$(call run,rm -rf out *.dSYM $(DEPSDIR))

distclean: clean

MALLOC_CHECK_=0
export MALLOC_CHECK_

.PRECIOUS: %.o
.PHONY: all clean clean-main clean-hook distclean \
	run run- run% prepare-check check check-all check-% testsummary
