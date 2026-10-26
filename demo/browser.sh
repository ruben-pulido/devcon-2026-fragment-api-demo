#!/usr/bin/env bash
#
# Opens the browser for the demo: a Chrome window on the right half of a
# 1920 x 1080 screen, next to demo/terminal.sh, with pages laid out at
# 1000 CSS pixels (the fragments admin shows the fragment sets beside their
# fragments only from 992), and three tabs: the portal's sign-in and both
# views of the store grid, which it starts if it is not running.
#
#   demo/browser.sh
#
# DEMO_BROWSER_X, DEMO_BROWSER_WIDTH, DEMO_BROWSER_HEIGHT (pixels) and
# DEMO_BROWSER_SCALE (default 0.93, so 930 pixels show 1000 CSS pixels) fit
# it to another screen.
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

setsid "$CHROME" \
	--force-device-scale-factor="${DEMO_BROWSER_SCALE:-0.93}" \
	--new-window \
	--no-default-browser-check \
	--no-first-run \
	--ozone-platform=x11 \
	--user-data-dir="$HOME/.cache/devcon-demo-browser" \
	--window-position="${DEMO_BROWSER_X:-990},0" \
	--window-size="${DEMO_BROWSER_WIDTH:-930},${DEMO_BROWSER_HEIGHT:-1080}" \
	"$LIFERAY_URL/c/portal/login" \
	"$GRID_URL/?cities=Madrid,London" \
	"$GRID_URL/" > /dev/null 2>&1 &

echo "Sign in as ${LIFERAY_AUTH%%:*}, then switch to dark mode with the moon button in the Product Menu."
