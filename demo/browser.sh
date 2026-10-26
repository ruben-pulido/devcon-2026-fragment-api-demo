#!/usr/bin/env bash
#
# Opens the browser for the demo: a Chrome window filling the screen to the
# right of demo/terminal.sh's window, with three tabs: the portal's sign-in
# and both views of the store grid, which it starts if it is not running.
#
#   demo/browser.sh
#
# The layout is for the presentation screen, DEMO_SCREEN (default 1920x1080,
# like the slides), whatever screen you rehearse on: GNOME's top bar takes the
# first DEMO_TOP_BAR pixels (default 32), and the browser fills the rest of
# the screen to the right of the demo terminal (DEMO_BROWSER_X, default: the
# terminal's right edge, or half the screen). DEMO_BROWSER_SCALE zooms it; by
# default, pages lay out at 1000 CSS pixels or more.
#
# It uses its own Chrome profile (~/.cache/devcon-demo-browser), so another
# portal's cached JavaScript never gets in the way and the sign-in is kept
# between runs. After signing in, switch to dark mode with the moon button in
# the Product Menu.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

source "$ROOT_DIR/lib.sh"

GRID_URL="http://localhost:${GRID_PORT:-8090}"

if [ -z "$CHROME" ]; then
	echo "Chrome or Chromium not found. Set CHROME to its path."

	exit 1
fi

if ! curl -s -o /dev/null "$GRID_URL/"; then
	setsid "$ROOT_DIR/demo/store-grid.py" > "$HOME/.cache/devcon-store-grid.log" 2>&1 &

	for _ in $(seq 1 20); do
		curl -s -o /dev/null "$GRID_URL/" && break

		sleep 0.5
	done
fi

screen="${DEMO_SCREEN:-1920x1080}"
top_bar="${DEMO_TOP_BAR:-32}"

# A window's X geometry includes the shadow it draws around itself
# (_GTK_FRAME_EXTENTS: left, right, top, bottom), so this works with the
# visible frames: the browser's starts where the terminal's ends.
extents() {
	xprop -id "$1" _GTK_FRAME_EXTENTS 2> /dev/null | tr -d ',' | awk '{ print ($3 == "" ? 0 : $3), ($4 == "" ? 0 : $4), ($5 == "" ? 0 : $5), ($6 == "" ? 0 : $6) }'
}

terminal_right=""
terminal=$(wmctrl -l 2> /dev/null | awk '/Ray’s Coffee demo/ { print $1 }' | tail -1)

if [ -n "$terminal" ]; then
	read -r terminal_x terminal_width < <(xdotool getwindowgeometry "$((terminal))" | awk '/Position/ { split($2, p, ","); x = p[1] } /Geometry/ { split($2, s, "x"); print x, s[1] }')
	read -r _ terminal_shadow_right _ _ < <(extents "$terminal")

	terminal_right=$(( terminal_x + terminal_width - terminal_shadow_right ))
fi

x="${DEMO_BROWSER_X:-${terminal_right:-$(( ${screen%x*} / 2 ))}}"
y="$top_bar"
width=$(( ${screen%x*} - x ))
height=$(( ${screen#*x} - top_bar ))

# Pages lay out at no less than 1000 CSS pixels, as in the video: the
# fragments admin needs 992 to show the fragment sets beside their fragments.
scale="${DEMO_BROWSER_SCALE:-$(awk -v width="$width" 'BEGIN { print (width < 1000 ? width / 1000 : 1) }')}"

setsid "$CHROME" \
	--force-device-scale-factor="$scale" \
	--new-window \
	--no-default-browser-check \
	--no-first-run \
	--ozone-platform=x11 \
	--user-data-dir="$HOME/.cache/devcon-demo-browser" \
	--window-position="$x,$y" \
	--window-size="$width,$height" \
	"$LIFERAY_URL/c/portal/login" \
	"$GRID_URL/?cities=Madrid,London" \
	"$GRID_URL/" > /dev/null 2>&1 &

pid=$!

if command -v wmctrl > /dev/null; then
	for _ in $(seq 1 40); do
		window=$(wmctrl -lp | awk -v pid="$pid" '$3 == pid { print $1 }' | tail -1)

		if [ -n "$window" ]; then
			sleep 0.5

			read -r left right top bottom < <(extents "$window")

			wmctrl -i -r "$window" -e "0,$(( x - left )),$(( y - top )),$(( width + left + right )),$(( height + top + bottom ))"

			break
		fi

		sleep 0.25
	done
fi

echo "Sign in as ${LIFERAY_AUTH%%:*}, then switch to dark mode with the moon button in the Product Menu."
