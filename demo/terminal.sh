#!/usr/bin/env bash
#
# Opens a terminal window sized for the demo: Source Code Pro Medium in a
# large size, 73 columns by 41 rows, in the demo kit's directory.
#
#   demo/terminal.sh             a shell, ready for ./demo.sh
#   demo/terminal.sh ./demo.sh   the demo, straight away
#
# DEMO_FONT_SIZE (points, default 16) scales it to the screen: the screens
# fit 73 x 41, so pick the largest size where the window still fits.
#
# Ptyxis keeps one font for all its windows, so this starts a separate
# Ptyxis with its own settings (the keyfile settings backend, in
# ~/.cache/devcon-demo-terminal), leaving your usual terminal untouched.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

FONT="${DEMO_FONT:-Source Code Pro Medium}"
SIZE="${DEMO_FONT_SIZE:-16}"

if ! command -v ptyxis > /dev/null; then
	echo "Ptyxis not found. Set your terminal to \"$FONT $SIZE\" (73 x 41) by hand."

	exit 1
fi

config="$HOME/.cache/devcon-demo-terminal"

mkdir -p "$config/glib-2.0/settings"

cat > "$config/glib-2.0/settings/keyfile" << EOF
[org/gnome/Ptyxis]
default-columns=uint32 73
default-rows=uint32 41
font-name='$FONT $SIZE'
restore-session=false
restore-window-size=false
use-system-font=false
EOF

command=()

if [ $# -gt 0 ]; then
	command=(-x "$*")
fi

GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$config" \
	setsid ptyxis --standalone --new-window --working-directory="$ROOT_DIR" --title="Ray’s Coffee demo" "${command[@]}" > /dev/null 2>&1 &
