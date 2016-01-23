PACKAGE_VERSION = `/bin/fgrep GK_V= genkernel | sed "s/.*GK_V='\([^']\+\)'/\1/"`
distdir = genkernel-$(PACKAGE_VERSION)
MANPAGE = genkernel.8
# Add off-Git/generated files here that need to be shipped with releases
EXTRA_DIST = $(MANPAGE) ChangeLog $(KCONF)

default: kconfig man

# First argument in the override file
# Second argument is the base file
BASE_KCONF = defaults/kernel-generic-config
ARCH_KCONF = $(wildcard arch/*/arch-config)
GENERATED_KCONF = $(subst arch-,generated-,$(ARCH_KCONF))
KCONF = $(GENERATED_KCONF)

debug:
	@echo "ARCH_KCONF=$(ARCH_KCONF)"
	@echo "GENERATED_KCONF=$(GENERATED_KCONF)"

kconfig: $(GENERATED_KCONF)
man: $(MANPAGE)

ChangeLog:
	git log >$@

clean:
	rm -f $(EXTRA_DIST)

check-git-repository:
	git diff --quiet || { echo 'STOP, you have uncommitted changes in the working directory' ; false ; }
	git diff --cached --quiet || { echo 'STOP, you have uncommitted changes in the index' ; false ; }

dist: check-git-repository distclean $(EXTRA_DIST)
	mkdir "$(distdir)"
	git ls-files -z | xargs -0 cp --no-dereference --parents --target-directory="$(distdir)" \
		$(EXTRA_DIST)
	tar cf "$(distdir)".tar "$(distdir)"
	xz -v "$(distdir)".tar
	rm -Rf "$(distdir)"

distclean: clean
	rm -Rf "$(distdir)" "$(distdir)".tar "$(distdir)".tar.xz

.PHONY: clean check-git-repository dist distclean kconfig

# Generic rules
%/generated-config: %/arch-config $(BASE_KCONF) merge.pl Makefile
	perl merge.pl $^ $(BASE_KCONF) > $@

%.8: doc/%.8.txt doc/asciidoc.conf Makefile genkernel
	a2x --conf-file=doc/asciidoc.conf --attribute="genkernelversion=$(PACKAGE_VERSION)" \
		 --format=manpage -D . "$<"
