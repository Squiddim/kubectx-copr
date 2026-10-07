# kubectx-copr

Fedora COPR packaging for [kubectx and kubens](https://github.com/ahmetb/kubectx).

```
sudo dnf copr enable squiddim/kubectx
sudo dnf install kubectx
```

## What it does

Builds both `kubectx` and `kubens` from the upstream source tag and installs
them with their bash, zsh and fish completions. `fzf` is a weak dependency for
interactive selection.

mock builds without network access, so `scripts/prepare-sources.sh` runs
`go mod vendor` and ships the modules as a second source tarball
(`kubectx-<version>-vendor.tar.gz`). It also writes a
`Provides: bundled(golang(...))` line for each module into the spec.

Builds for x86_64 and aarch64.

## Updates

A GitHub Actions cron polls upstream every 6h and POSTs the COPR webhook when
the version changes. COPR then clones this repo and runs `scripts/prepare-sources.sh`,
which resolves the latest release itself.

## Setup

Needs `copr-cli` and a token at `~/.config/copr` from
<https://copr.fedorainfracloud.org/api/>.

```bash
./scripts/copr-setup.sh
```

Then store the printed webhook URL as the `COPR_WEBHOOK_URL` secret and set the
`COPR_OWNER` / `COPR_PROJECT` variables.

## Local test

```bash
podman run --rm -v "$PWD":/src:ro,z fedora:44 bash -c '
  dnf -y install rpm-build curl python3 tar gawk golang go-rpm-macros
  cp -r /src /tmp/repo && cd /tmp/repo
  ./scripts/prepare-sources.sh --outdir /tmp/out --srpm
  rpmbuild --rebuild /tmp/out/*.src.rpm --define "_topdir /tmp/rpmbuild"
  dnf -y install /tmp/rpmbuild/RPMS/x86_64/kubectx-0*.rpm
  rpm -V kubectx && kubectx --version
'
```
