#!/bin/bash
# Terminal fallback for the portable zip. Links the bundled CLI into the first
# writable directory: /usr/local/bin, then ~/.local/bin.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/AES Open Crypt.app}"
CLI="$APP/Contents/Resources/bin/aesopen"

if [[ ! -x "$CLI" ]]; then
    echo "aesopen not found at $CLI" >&2
    echo "Build the app first: ./scripts/build-app.sh" >&2
    exit 1
fi

install_link() {
    local dir="$1"
    local link="$dir/aesopen"

    mkdir -p "$dir"

    if [[ -L "$link" ]]; then
        local destination
        destination="$(readlink "$link")"
        if [[ "$destination" = "$CLI" ]]; then
            echo "aesopen is already linked at $link"
            return 0
        fi
        case "$destination" in
            */"AES Open Crypt.app/Contents/Resources/bin/aesopen") ;;
            *)
                echo "Refusing to replace $link (points to $destination)" >&2
                return 1
                ;;
        esac
    elif [[ -e "$link" ]]; then
        echo "Refusing to replace $link" >&2
        return 1
    fi

    ln -sfn "$CLI" "$link"
    echo "Linked $link -> $CLI"
}

if [[ -d /usr/local/bin && -w /usr/local/bin ]] || { [[ ! -d /usr/local/bin ]] && [[ -w /usr/local ]]; }; then
    install_link /usr/local/bin
elif mkdir -p "$HOME/.local/bin" 2>/dev/null && [[ -w "$HOME/.local/bin" ]]; then
    install_link "$HOME/.local/bin"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *)
            echo "Add this to your shell profile:"
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            ;;
    esac
else
    echo "No writable bin directory found. Run:" >&2
    echo "  sudo mkdir -p /usr/local/bin && sudo ln -sfn '$CLI' /usr/local/bin/aesopen" >&2
    exit 1
fi
