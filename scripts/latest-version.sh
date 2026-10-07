#!/usr/bin/bash
# Print the latest published upstream release as an RPM Version (tag minus "v").
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-ahmetb/kubectx}"

# Optional: only raises the API rate limit from 60/h to 5000/h.
auth=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

response=$(curl --fail-with-body -sSL "${auth[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest")

tag=$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')

if [[ "$tag" != v* ]]; then
    echo "Upstream tag '${tag}' lacks the expected 'v' prefix" >&2
    exit 1
fi
version="${tag#v}"

# Catch a tag that is not a legal RPM Version here, not inside rpmbuild.
if [[ ! "$version" =~ ^[0-9][0-9a-zA-Z.+~]*$ ]]; then
    echo "Upstream tag '${tag}' is not usable as an RPM Version" >&2
    exit 1
fi

printf '%s\n' "$version"
