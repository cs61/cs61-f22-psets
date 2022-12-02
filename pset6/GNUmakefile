PROGRAMS := ftxunlocked ftxxfer ftxrocket ftxblockchain
default: $(PROGRAMS)

# Default optimization level
O ?= 2
X86 = 0
PTHREAD = 1
-include build/rules.mk

%.o: %.cc $(BUILDSTAMP)
	$(call run,$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(DEPCFLAGS) $(O) -o $@ -c,COMPILE,$<)

$(PROGRAMS): %: io61.o helpers.o ftxhelpers.o %.o
	$(call run,$(CXX) $(CXXFLAGS) $(LDFLAGS) $(O) -o $@ $^ $(LIBS),LINK $@)


default:
	@echo "*** Run 'make check' to check your work."

all: $(PROGRAMS)
	@:

check:
	perl check.pl

check-%:
	perl check.pl $(subst check-,,$@)

clean: clean-main
clean-main:
	$(call run,rm -f $(PROGRAMS) *.o core *.core,CLEAN)
	$(call run,rm -rf $(DEPSDIR) files *.dSYM)

distclean: clean

.PRECIOUS: %.o
.PHONY: all default clean clean-main clean-hook distclean \
	tests stdio slow check check-% prepare-check
export STRACE NOSTDIO TRIALS MAXTIME TMP V
