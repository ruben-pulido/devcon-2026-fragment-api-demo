#!/usr/bin/env bash
#
# Opens a terminal window sized for the demo: Source Code Pro Medium, the left
# half of the screen below GNOME's top bar (at least 41 rows) (DEMO_TERMINAL_WIDTH, default half of
# DEMO_SCREEN's width; about 95 columns), in the demo kit's directory. GNOME's
# top bar takes DEMO_TOP_BAR pixels (default 32). Next to demo/browser.sh.
#
#   demo/terminal.sh             a shell, ready for ./demo.sh
#   demo/terminal.sh ./demo.sh   the demo, straight away
#
# The size is for the presentation screen, not the one you rehearse on:
# the demo's screens need 41 rows, which at DEMO_FONT_SIZE 13 (points, the
# default) just fit the height of a 1920 x 1080 screen under GNOME's top bar,
# at 100% scaling. For a taller presentation screen, go bigger.
#
# Ptyxis keeps one font for all its windows, so this starts a separate
# Ptyxis with its own settings (the keyfile settings backend, in
# ~/.cache/devcon-demo-terminal), leaving your usual terminal untouched. Its
# zsh skips your own configuration: the prompt shows only the path, and no
# tmux or theme gets in the way.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

FONT="${DEMO_FONT:-Source Code Pro Medium}"
SIZE="${DEMO_FONT_SIZE:-13}"

if ! command -v ptyxis > /dev/null; then
	echo "Ptyxis not found. Set your terminal to \"$FONT $SIZE\" with 41 rows on half the screen, by hand."

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
disable-padding=true
restore-window-size=false
use-system-font=false
EOF

mkdir -p "$config/zsh"

cat > "$config/zsh/.zshrc" << 'EOF'
export PATH="$HOME/.local/bin:$PATH"

PROMPT=$'%~>\n'
RPROMPT=''

if [ -n "${DEMO_COMMAND:-}" ]; then
	command="$DEMO_COMMAND"
	unset DEMO_COMMAND
	eval "$command"
fi
EOF

touch "$config/zsh/.zprofile"


env -u TMUX -u TMUX_PANE DEMO_COMMAND="$*" GDK_BACKEND=x11 GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$config" ZDOTDIR="$config/zsh" \
	setsid ptyxis --standalone --new-window --working-directory="$ROOT_DIR" --title="Ray’s Coffee demo" > /dev/null 2>&1 &

pid=$!

# A window's X geometry includes the shadow it draws around itself
# (_GTK_FRAME_EXTENTS: left, right, top, bottom), so the visible frame is
# placed by offsetting the window by its shadow.
if command -v wmctrl > /dev/null && command -v xprop > /dev/null; then
	for _ in $(seq 1 40); do
		window=$(wmctrl -lp | awk -v pid="$pid" '$3 == pid { print $1; exit }')

		if [ -n "$window" ]; then
			sleep 0.5

			read -r left _ top _ < <(xprop -id "$window" _GTK_FRAME_EXTENTS | tr -d ',' | awk '{ print $3, $4, $5, $6 }')

			read -r _ right _ bottom < <(xprop -id "$window" _GTK_FRAME_EXTENTS | tr -d ',' | awk '{ print $3, $4, $5, $6 }')

			screen="${DEMO_SCREEN:-1920x1080}"

			wmctrl -i -r "$window" -e "0,$(( ${DEMO_TERMINAL_X:-0} - ${left:-0} )),$(( ${DEMO_TOP_BAR:-32} - ${top:-0} )),$(( ${DEMO_TERMINAL_WIDTH:-$(( ${screen%x*} / 2 ))} + ${left:-0} + ${right:-0} )),$(( ${screen#*x} - ${DEMO_TOP_BAR:-32} + ${top:-0} + ${bottom:-0} ))"
			wmctrl -i -a "$window"

			break
		fi

		sleep 0.25
	done
fi
