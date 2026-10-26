#!/usr/bin/env bash
#
# Opens the browser for the demo: a Chrome window filling the screen to the
# right of demo/terminal.sh's window, with three tabs: the portal's sign-in
# and both views of the store grid, which it starts if it is not running.
#
#   demo/browser.sh
#
# DEMO_BROWSER_X (default: the right edge of the demo terminal, or 782) and
# DEMO_BROWSER_SCALE (default 1) fit it to another screen; the fragments admin
# shows the fragment sets beside their fragments only when the page is at
# least 992 CSS pixels wide.
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

read -r area_x area_y area_width area_height < <(xprop -root _NET_WORKAREA 2> /dev/null | tr -d ',' | awk '{ print $3, $4, $5, $6 }')

terminal=$(wmctrl -lG 2> /dev/null | awk '/Ray’s Coffee demo/ { print $3 + $5; exit }')

x="${DEMO_BROWSER_X:-${terminal:-782}}"
y="${area_y:-0}"
width=$(( ${area_width:-1920} - x ))
height="${area_height:-1080}"

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
