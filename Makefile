PACKAGE_VERSION = `/bin/fgrep GK_V= genkernel | sed "s/.*GK_V='\([^']\+\)'/\1/"`
distdir = genkernel-$(PACKAGE_VERSION)
KCONF = $(shell ls arch/*/arch-config | sed 's/arch-/generated-/g')

# Add off-Git/generated files here that need to be shipped with releases
EXTRA_DIST = genkernel.8 ChangeLog $(KCONF)

default: $(KCONF) genkernel.8

$(KCONF):
	perl merge.pl defaults/kernel-generic-config $(dir $@)arch-config > $@

genkernel.8: doc/genkernel.8.txt doc/asciidoc.conf Makefile genkernel
	a2x --conf-file=doc/asciidoc.conf --attribute="genkernelversion=$(PACKAGE_VERSION)" \
		 --format=manpage -D . "$<"

ChangeLog:
	git log >$@

clean:
	rm -f $(EXTRA_DIST)

check-git-repository:
	git diff --quiet || { echo 'STOP, you have uncommitted changes in the working directory' ; false ; }
	git diff --cached --quiet || { echo 'STOP, you have uncommitted changes in the index' ; false ; }

dist: check-git-repository $(EXTRA_DIST) distclean
	mkdir "$(distdir)"
	git ls-files -z | xargs -0 cp --no-dereference --parents --target-directory="$(distdir)" \
		$(EXTRA_DIST)
	tar cf "$(distdir)".tar "$(distdir)"
	xz -v "$(distdir)".tar
	rm -Rf "$(distdir)"

distclean: clean
	rm -Rf "$(distdir)" "$(distdir)".tar "$(distdir)".tar.xz

.PHONY: clean check-git-repository dist distclean
