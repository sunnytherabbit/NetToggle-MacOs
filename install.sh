#!/bin/sh
set -e

INSTALL_DIR="/usr/local/bin"
HELPER_NAME="NetToggleHelper"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Compiling $HELPER_NAME..."
clang -O2 -o "$SCRIPT_DIR/Helper/$HELPER_NAME" "$SCRIPT_DIR/Helper/$HELPER_NAME.c"

echo "Installing $HELPER_NAME to $INSTALL_DIR (requires root)..."
if [ -d "$INSTALL_DIR" ]; then
    sudo cp "$SCRIPT_DIR/Helper/$HELPER_NAME" "$INSTALL_DIR/$HELPER_NAME"
    sudo chown root:wheel "$INSTALL_DIR/$HELPER_NAME"
    sudo chmod 4755 "$INSTALL_DIR/$HELPER_NAME"
else
    INSTALL_DIR="$HOME/.local/bin"
    echo "/usr/local/bin does not exist. Falling back to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_DIR/Helper/$HELPER_NAME" "$INSTALL_DIR/$HELPER_NAME"
    sudo chown root:wheel "$INSTALL_DIR/$HELPER_NAME"
    sudo chmod 4755 "$INSTALL_DIR/$HELPER_NAME"
fi

# Try to remove any quarantine attribute and ad-hoc sign for local use.
if command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$INSTALL_DIR/$HELPER_NAME" 2>/dev/null || true
fi
if command -v codesign >/dev/null 2>&1; then
    codesign --sign - --force "$INSTALL_DIR/$HELPER_NAME" 2>/dev/null || true
fi

# Re-apply setuid in case codesign stripped it.
sudo chmod 4755 "$INSTALL_DIR/$HELPER_NAME"

echo "Done. Verify with: ls -la $INSTALL_DIR/$HELPER_NAME"
