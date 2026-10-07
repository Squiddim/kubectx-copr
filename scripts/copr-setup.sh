#!/usr/bin/bash
# One-time COPR project setup. Idempotent: safe to re-run to change chroots.
# Requires an API token at ~/.config/copr (a file, not a directory) from
# https://copr.fedorainfracloud.org/api/
set -euo pipefail

COPR_PROJECT="${COPR_PROJECT:-kubectx}"
COPR_SOURCE_REPO="${COPR_SOURCE_REPO:-https://github.com/Squiddim/kubectx-copr}"
CHROOTS="${CHROOTS:-fedora-43-x86_64 fedora-43-aarch64 fedora-44-x86_64 fedora-44-aarch64 fedora-45-x86_64 fedora-45-aarch64 fedora-rawhide-x86_64 fedora-rawhide-aarch64}"
CONFIG="${COPR_CONFIG:-${HOME}/.config/copr}"
API="https://copr.fedorainfracloud.org"

if ! command -v copr-cli >/dev/null; then
    echo "copr-cli not found. Install it with: sudo dnf install copr-cli" >&2
    exit 1
fi
if [[ ! -f "$CONFIG" ]]; then
    echo "No API token at ${CONFIG}. Get one from ${API}/api/" >&2
    echo "Note that it is a plain file, not a directory." >&2
    exit 1
fi

# `copr-cli whoami` echoes the config's username without calling the API, so it
# reports success even with a dead token. Check the embedded expiry instead.
expiry=$(sed -n 's/^#[[:space:]]*expiration date:[[:space:]]*//p' "$CONFIG" | head -1)
if [[ -n "$expiry" ]]; then
    if [[ $(date -d "$expiry" +%s) -lt $(date +%s) ]]; then
        echo "API token expired on ${expiry} (today is $(date +%F))." >&2
        echo "Renew it at ${API}/api/ and replace the contents of ${CONFIG}." >&2
        exit 1
    fi
    echo ">>> Token valid until ${expiry}"
fi

if [[ "$(stat -c '%a' "$CONFIG")" != "600" ]]; then
    echo ">>> Tightening permissions on ${CONFIG} (was $(stat -c '%a' "$CONFIG"))"
    chmod 600 "$CONFIG"
fi

# The FAS name, which need not match $USER or the GitHub account.
COPR_OWNER=$(python3 -c "
import configparser, sys
c = configparser.ConfigParser(); c.read('$CONFIG')
print(c['copr-cli']['username'])
")
echo ">>> COPR owner: ${COPR_OWNER}"

chroot_args=()
for chroot in $CHROOTS; do
    chroot_args+=(--chroot "$chroot")
done

# Ask the API whether the project exists rather than inferring it from a failed
# `create`, which would also swallow real errors like an expired token.
code=$(curl -sS -o /dev/null -w '%{http_code}' \
    "${API}/api_3/project?ownername=${COPR_OWNER}&projectname=${COPR_PROJECT}")

if [[ "$code" == "200" ]]; then
    echo ">>> Project '${COPR_OWNER}/${COPR_PROJECT}' exists, updating chroots"
    copr-cli modify "$COPR_PROJECT" "${chroot_args[@]}"
else
    echo ">>> Creating project '${COPR_OWNER}/${COPR_PROJECT}'"
    copr-cli create "$COPR_PROJECT" "${chroot_args[@]}" \
        --description "kubectx and kubens - switch between Kubernetes contexts and namespaces. Built from upstream source." \
        --instructions "sudo dnf copr enable ${COPR_OWNER}/${COPR_PROJECT} && sudo dnf install kubectx"
fi

# Keeping the build logic in git rather than the COPR web form means it stays
# reviewable and reproducible locally.
script=$(mktemp)
trap 'rm -f "$script"' EXIT
cat > "$script" <<CUSTOM
#!/bin/sh -x
git clone --depth 1 ${COPR_SOURCE_REPO} kubectx-copr
cd kubectx-copr
./scripts/prepare-sources.sh --outdir "\$COPR_RESULTDIR"
CUSTOM

# Without --webhook-rebuild on, COPR accepts the POST and does nothing.
pkg_args=(
    --name kubectx
    --script "$script"
    --script-builddeps "git curl python3 rpm-build tar gawk golang"
    --script-resultdir "."
    --webhook-rebuild on
)

if copr-cli get-package "$COPR_PROJECT" --name kubectx >/dev/null 2>&1; then
    echo ">>> Updating existing 'kubectx' package"
    copr-cli edit-package-custom "$COPR_PROJECT" "${pkg_args[@]}"
else
    echo ">>> Adding 'kubectx' package (custom source method)"
    copr-cli add-package-custom "$COPR_PROJECT" "${pkg_args[@]}"
fi

cat <<DONE

>>> Done.

Next, wire up the trigger:

  1. Copy the *custom* webhook URL from:
       ${API}/coprs/${COPR_OWNER}/${COPR_PROJECT}/integrations/

  2. Store it, and the project coordinates, on the GitHub repository:

       gh secret set COPR_WEBHOOK_URL --body '<url>'
       gh variable set COPR_OWNER --body '${COPR_OWNER}'
       gh variable set COPR_PROJECT --body '${COPR_PROJECT}'

  3. Kick off the first build:

       copr-cli build-package ${COPR_PROJECT} --name kubectx

DONE
