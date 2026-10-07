#!/usr/bin/bash
# Stage the spec and sources for the latest upstream release into --outdir.
#
# COPR's custom source method wants exactly that and builds the SRPM itself; it
# rejects a prebuilt one. --srpm additionally builds it, for .copr/Makefile and
# for local testing.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM_REPO="${UPSTREAM_REPO:-ahmetb/kubectx}"
PACKAGER="${PACKAGER:-Squiddim <82903357+Squiddim@users.noreply.github.com>}"

outdir="${COPR_RESULTDIR:-$PWD}"
version=""
build_srpm=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --outdir)  outdir="$2"; shift 2 ;;
        --version) version="${2#v}"; shift 2 ;;
        --srpm)    build_srpm=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$version" ]]; then
    version=$("${REPO_ROOT}/scripts/latest-version.sh")
fi
mkdir -p "$outdir"
outdir=$(cd "$outdir" && pwd)
echo ">>> Preparing kubectx ${version} in ${outdir}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tarball="kubectx-${version}.tar.gz"
echo ">>> Fetching ${tarball}"
curl --fail-with-body -sSL -o "${outdir}/${tarball}" \
    "https://github.com/${UPSTREAM_REPO}/archive/v${version}/${tarball}"

# An error page or truncated transfer would otherwise surface much later.
echo ">>> Verifying source contents"
tar -xzf "${outdir}/${tarball}" -C "$work"
src="${work}/kubectx-${version}"
for required in go.mod go.sum LICENSE cmd/kubectx/main.go cmd/kubens/main.go \
        completion/kubectx.bash completion/_kubens.zsh completion/kubens.fish; do
    if [[ ! -f "${src}/${required}" ]]; then
        echo "Source is missing '${required}' - refusing to build" >&2
        exit 1
    fi
done

# mock builds offline, so the module dependencies travel as a second tarball.
# The module cache stays in the scratch dir; it is read-only by default, which
# would make the trap's rm fail.
echo ">>> Vendoring Go modules"
(
    cd "$src"
    GOFLAGS=-modcacherw GOMODCACHE="${work}/gomodcache" GOPATH="${work}/gopath" \
        go mod vendor
)
vendor_tarball="kubectx-${version}-vendor.tar.gz"
tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner \
    -C "$src" -czf "${outdir}/${vendor_tarball}" vendor

# Fedora's bundling policy wants one Provides per vendored module.
provides=$(awk '/^# / && $3 ~ /^v/ {
        v = $3; sub(/^v/, "", v); gsub(/-/, "~", v); gsub(/\+incompatible$/, "", v)
        printf "Provides:       bundled(golang(%s)) = %s\n", $2, v
    }' "${src}/vendor/modules.txt")

# Passed via the environment: awk -v rejects multi-line values.
VERSION="$version" PROVIDES="$provides" awk '
    /^__BUNDLED_PROVIDES__$/ { print ENVIRON["PROVIDES"]; next }
    { gsub(/__VERSION__/, ENVIRON["VERSION"]); print }
' "$REPO_ROOT/kubectx.spec" > "${outdir}/kubectx.spec"

# rpmbuild requires C locale month and day names.
changelog_date=$(LC_ALL=C date '+%a %b %d %Y')
cat >> "${outdir}/kubectx.spec" <<CHANGELOG
* ${changelog_date} ${PACKAGER} - ${version}-1
- Update to upstream release ${version}
- https://github.com/${UPSTREAM_REPO}/releases/tag/v${version}
CHANGELOG

echo ">>> Staged: $(cd "$outdir" && ls)"

if [[ "$build_srpm" == "1" ]]; then
    echo ">>> Building source package"
    rpmbuild -bs "${outdir}/kubectx.spec" \
        --define "_topdir ${outdir}" \
        --define "_sourcedir ${outdir}" \
        --define "_srcrpmdir ${outdir}" \
        --define "dist %{nil}"
    echo ">>> Wrote: $(ls "${outdir}"/kubectx-*.src.rpm)"
fi
