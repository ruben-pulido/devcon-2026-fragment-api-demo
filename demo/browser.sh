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
# terminal's right edge, or 782). DEMO_BROWSER_SCALE (default 1) zooms it; the
# fragments admin shows the fragment sets beside their fragments only when
# the page is at least 992 CSS pixels wide.
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

terminal=$(xdotool search --name 'Ray’s Coffee demo' getwindowgeometry 2> /dev/null | awk '/Geometry/ { split($2, size, "x"); print size[1]; exit }')

x="${DEMO_BROWSER_X:-${terminal:-782}}"
y="$top_bar"
width=$(( ${screen%x*} - x ))
height=$(( ${screen#*x} - top_bar ))

setsid "$CHROME" \
	--force-device-scale-factor="${DEMO_BROWSER_SCALE:-1}" \
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
			wmctrl -i -r "$window" -e "0,$x,$y,$width,$height"

			break
		fi

		sleep 0.25
	done
fi

echo "Sign in as ${LIFERAY_AUTH%%:*}, then switch to dark mode with the moon button in the Product Menu."
