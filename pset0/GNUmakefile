# Default optimization level
all: always
	@echo '❌ Try `make test-hello` or `make PROGRAMNAME`.' 1>&2; exit 1

UBSAN ?= 1

-include build/rules.mk

%: %.o always
	$(call run,$(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) $< -o,LINK,$@)

%.o: %.cc always
	$(call run,$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(DEPCFLAGS) $(O) -o $@ -c,COMPILE,$<)

test: test-hello

test-hello: always
	@if echo awesome | cmp hello.txt - 2>/dev/null; then echo '✅ Cool! hello.txt exists and has the right contents.'; elif test -r hello.txt; then echo '❌ hello.txt does not have the right contents.'; exit 1; else echo '❌ hello.txt cannot be read.'; exit 1; fi

clean: always
	rm -f *.o exiter

.PRECIOUS: %.o
.PHONY: all test test-hello clean
