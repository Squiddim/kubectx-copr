# Version is substituted by scripts/prepare-sources.sh.
%global upstream_version __VERSION__

Name:           kubectx
Version:        %{upstream_version}
Release:        1%{?dist}
Summary:        Faster way to switch between clusters and namespaces in kubectl

# kubectx itself is Apache-2.0. The rest comes from vendored Go modules.
License:        Apache-2.0 AND BSD-3-Clause AND ISC AND MIT
URL:            https://github.com/ahmetb/kubectx
Source0:        %{url}/archive/v%{upstream_version}/%{name}-%{upstream_version}.tar.gz
# Produced by scripts/prepare-sources.sh with `go mod vendor`, because mock
# builds without network access.
Source1:        %{name}-%{upstream_version}-vendor.tar.gz

BuildRequires:  golang >= 1.25
BuildRequires:  go-rpm-macros

# Interactive selection when called without arguments in a terminal.
Recommends:     fzf

# Generated from vendor/modules.txt by scripts/prepare-sources.sh.
__BUNDLED_PROVIDES__

%description
kubectx is a tool to switch between contexts (clusters) on kubectl faster.

kubens is a tool to switch between Kubernetes namespaces (and configure them
for kubectl) easily.

%prep
%autosetup -p1
# The vendor tarball unpacks to vendor/.
tar -xzf %{SOURCE1}

%build
export GO111MODULE=on
export GOFLAGS=-mod=vendor
# goreleaser injects the tag without its leading "v".
export LDFLAGS="-X main.version=%{version}"
mkdir -p bin
for cmd in kubectx kubens; do
    %gobuild -o bin/${cmd} ./cmd/${cmd}
done

%install
install -Dpm0755 bin/kubectx %{buildroot}%{_bindir}/kubectx
install -Dpm0755 bin/kubens %{buildroot}%{_bindir}/kubens

install -Dpm0644 completion/kubectx.bash %{buildroot}%{bash_completions_dir}/kubectx
install -Dpm0644 completion/kubens.bash %{buildroot}%{bash_completions_dir}/kubens
install -Dpm0644 completion/_kubectx.zsh %{buildroot}%{zsh_completions_dir}/_kubectx
install -Dpm0644 completion/_kubens.zsh %{buildroot}%{zsh_completions_dir}/_kubens
install -Dpm0644 completion/kubectx.fish %{buildroot}%{fish_completions_dir}/kubectx.fish
install -Dpm0644 completion/kubens.fish %{buildroot}%{fish_completions_dir}/kubens.fish

# Collect the vendored modules' license texts for %%license.
find vendor -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' \
    -o -iname 'NOTICE*' -o -iname 'PATENTS*' \) ! -name '*.go' \
    -printf '%%%%license %%p\n' | sort > vendor-licenses.list

%check
export GO111MODULE=on
export GOFLAGS=-mod=vendor
go test ./...
for cmd in kubectx kubens; do
    test "$(bin/${cmd} --version)" = "%{version}"
done

%files -f vendor-licenses.list
%license LICENSE
%doc README.md
%{_bindir}/kubectx
%{_bindir}/kubens
%{bash_completions_dir}/kubectx
%{bash_completions_dir}/kubens
%{zsh_completions_dir}/_kubectx
%{zsh_completions_dir}/_kubens
%{fish_completions_dir}/kubectx.fish
%{fish_completions_dir}/kubens.fish

%changelog
