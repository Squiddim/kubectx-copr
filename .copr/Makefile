# COPR make_srpm entrypoint, and the way to reproduce a build locally:
#   make -f .copr/Makefile srpm outdir=/tmp/kubectx-srpm
# The live project uses the custom source method instead (see README), but both
# call the same script.
srpm:
	dnf -y install --setopt=install_weak_deps=False curl gawk golang python3 rpm-build tar
	./scripts/prepare-sources.sh --outdir $(outdir) --srpm

.PHONY: srpm
