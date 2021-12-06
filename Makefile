PACKAGENAME=Cython
PYTHON?=python
TESTOPTS?=
REPO = git://github.com/cython/cython.git
VERSION?=$(shell sed -ne 's|^__version__\s*=\s*"\([^"]*\)".*|\1|p' Cython/Shadow.py)

MANYLINUX_CFLAGS=-O3 -g0 -mtune=generic -pipe -fPIC
MANYLINUX_LDFLAGS=-flto
MANYLINUX_IMAGES= \
	manylinux1_x86_64 \
	manylinux1_i686 \
	musllinux_1_1_x86_64 \
	manylinux_2_24_x86_64 \
	manylinux_2_24_i686 \
	manylinux_2_24_aarch64 \
#	manylinux_2_24_ppc64le \
#	manylinux_2_24_s390x

all:    local

local:
	${PYTHON} setup.py build_ext --inplace

sdist: dist/$(PACKAGENAME)-$(VERSION).tar.gz

dist/$(PACKAGENAME)-$(VERSION).tar.gz:
	$(PYTHON) setup.py sdist

pywheel: dist/$(PACKAGENAME)-$(VERSION)-py2.py3-none-any.whl

dist/$(PACKAGENAME)-$(VERSION)-py2.py3-none-any.whl:
	${PYTHON} setup.py bdist_wheel --no-cython-compile --universal
	[ -f "$@" ]  # check that we generated the expected universal wheel

TMPDIR = .repo_tmp
.git: .gitrev
	rm -rf $(TMPDIR)
	git clone -n $(REPO) $(TMPDIR)
	cd $(TMPDIR) && git reset -q "$(shell cat .gitrev)"
	mv $(TMPDIR)/.git .
	rm -rf $(TMPDIR)
	git ls-files -d | xargs git checkout --

# Create a git repo from an unpacked source directory.
repo: .git


clean:
	@echo Cleaning Source
	@rm -fr build
	@rm -f *.py[co] */*.py[co] */*/*.py[co] */*/*/*.py[co]
	@rm -f *.so */*.so */*/*.so
	@rm -f *.pyd */*.pyd */*/*.pyd
	@rm -f *~ */*~ */*/*~
	@rm -f core */core
	@rm -f Cython/Compiler/*.c
	@rm -f Cython/Plex/*.c
	@rm -f Cython/Tempita/*.c
	@rm -f Cython/Runtime/refnanny.c
	@(cd Demos; $(MAKE) clean)

testclean:
	rm -fr BUILD TEST_TMP

test:	testclean
	${PYTHON} runtests.py -vv ${TESTOPTS}

s5:
	$(MAKE) -C Doc/s5 slides

qemu-user-static:
	docker run --rm --privileged hypriot/qemu-register

wheel_manylinux: sdist $(addprefix wheel_,$(MANYLINUX_IMAGES))
$(addprefix wheel_,$(filter-out %_x86_64, $(filter-out %_i686, $(MANYLINUX_IMAGES)))): qemu-user-static

wheel_%: dist/$(PACKAGENAME)-$(VERSION).tar.gz
	echo "Building wheels for $(PACKAGENAME) $(VERSION)"
	mkdir -p wheelhouse_$(subst wheel_,,$@)
	time docker run --rm -t \
		-v $(shell pwd):/io \
		-e CFLAGS="$(MANYLINUX_CFLAGS) $(if $(patsubst %aarch64,,$@),-march=core2,-march=armv8-a -mtune=cortex-a72)" \
		-e LDFLAGS="$(LDFLAGS) -fPIC" \
		-e WHEELHOUSE=wheelhouse$(subst wheel_musllinux,,$(subst wheel_manylinux,,$@)) \
		quay.io/pypa/$(subst wheel_,,$@) \
		bash -c 'for PYBIN in /opt/python/cp*/bin; do \
		    $$PYBIN/python -V; \
		    { $$PYBIN/pip wheel -w /io/$$WHEELHOUSE /io/$< & } ; \
		    done; wait; \
		    for whl in /io/$$WHEELHOUSE/$(PACKAGENAME)-$(VERSION)-*-linux_*.whl; do auditwheel repair $$whl -w /io/$$WHEELHOUSE; done'
