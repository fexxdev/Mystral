#!/usr/bin/env bash
set -euo pipefail

# Manages the Ed25519 key that signs Mystral update DMGs.
#   ./scripts/update-key.sh generate   create the key in the login Keychain, print the public key
#   ./scripts/update-key.sh public     print the public key of the stored key
#   ./scripts/update-key.sh private    print the private key, for an offline backup only
# The private key never appears in argv: it moves through stdin and shell variables.

SERVICE="com.fexxdev.Mystral.update-signing"
ACCOUNT="ed25519-private-key"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNER=(swift "$PROJECT_ROOT/scripts/update-signing.swift")

read_private_key() {
    /usr/bin/security find-generic-password -s "$SERVICE" -a "$ACCOUNT" -w
}

case "${1:-}" in
    generate)
        if read_private_key >/dev/null 2>&1; then
            echo "A key already exists in the Keychain ($SERVICE); refusing to overwrite it." >&2
            exit 1
        fi
        private_key="$("${SIGNER[@]}" generate)"
        # security -i reads the command from stdin, keeping the key out of the process list.
        printf 'add-generic-password -s %s -a %s -l "Mystral update signing key" -T /usr/bin/security -w %s\n' \
            "$SERVICE" "$ACCOUNT" "$private_key" | /usr/bin/security -i
        printf '%s' "$private_key" | "${SIGNER[@]}" public-key
        ;;
    public)
        read_private_key | "${SIGNER[@]}" public-key
        ;;
    private)
        read_private_key
        ;;
    *)
        echo "usage: $0 generate | public | private" >&2
        exit 1
        ;;
esac
