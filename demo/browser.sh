#!/usr/bin/env bash
#
# Opens the browser for the demo: a Chrome window filling the screen to the
# right of demo/terminal.sh's window, with three tabs: the portal's sign-in
# and both views of the store grid, which it starts if it is not running.
#
#   demo/browser.sh         the sign-in and both views of the store grid
#   demo/browser.sh --all   one tab for every screen the demo shows, in order
#
# Those screens are also on the bookmarks bar. The design library's own
# screens are not among them, as its URLs change every time it is created, so
# open it from the Design Libraries list.
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

FRAGMENTS="/~/control_panel/manage/-/fragments/fragment_collections?_com_liferay_fragment_web_portlet_FragmentPortlet_fragmentCollectionExternalReferenceCode"
RESOURCES="&_com_liferay_fragment_web_portlet_FragmentPortlet_tabs1=resources"
PAGES="/~/control_panel/manage?p_p_id=com_liferay_layout_admin_web_portlet_GroupPagesPortlet"
MCP_PORTLET=com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet

# Every screen the demo shows, in order: NUMBER|TITLE|URL. The number is the
# act where the screen first appears and its order in it; it names the
# bookmark, and the titles are printed as a legend.
bookmarks=(
	"0.1|Sign in|$LIFERAY_URL/c/portal/login"
	"1.1|Madrid: Ray’s Store fragments|$LIFERAY_URL/group/ray-s-coffee-madrid$FRAGMENTS=rays-store"
	"1.2|Madrid: Ray’s Campaigns fragments|$LIFERAY_URL/group/ray-s-coffee-madrid$FRAGMENTS=$FRAGMENT_SET_ERC"
	"1.3|Madrid: Ray’s Campaigns resources|$LIFERAY_URL/group/ray-s-coffee-madrid$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES"
	"1.4|Madrid: pages|$LIFERAY_URL/group/ray-s-coffee-madrid$PAGES"
	"1.5|Madrid store page|$LIFERAY_URL/web/ray-s-coffee-madrid/store-home"
	"2.1|London: Ray’s Store fragments|$LIFERAY_URL/group/ray-s-coffee-london$FRAGMENTS=rays-store"
	"2.2|Design Libraries (open Ray’s Design Library from here)|$LIFERAY_URL/group/control_panel/manage?p_p_id=com_liferay_design_library_web_internal_portlet_DesignLibraryAdminPortlet"
	"3.1|Store grid: Madrid and London|$GRID_URL/?cities=Madrid,London"
	"4.1|MCP Server: profiles|$LIFERAY_URL/group/control_panel/manage?p_p_id=$MCP_PORTLET"
	"4.2|MCP Server: the devcon profile's tools|$LIFERAY_URL/group/control_panel/manage?p_p_id=$MCP_PORTLET&p_p_lifecycle=0&p_p_state=maximized&_${MCP_PORTLET}_mvcRenderCommandName=%2Fmcp_server%2Fedit_profile&_${MCP_PORTLET}_profileERC=devcon&_${MCP_PORTLET}_tab=tools"
	"6.1|Store grid: all eight stores|$GRID_URL/"
)

urls=("$LIFERAY_URL/c/portal/login" "$GRID_URL/?cities=Madrid,London" "$GRID_URL/")

if [ "${1:-}" = --all ]; then
	urls=()

	for bookmark in "${bookmarks[@]}"; do
		urls+=("${bookmark#*|*|}")
	done
fi

profile="$HOME/.cache/devcon-demo-browser"

# A Chrome already running on the demo's profile would only open one more
# window, where it last was; closing it starts one in the right place (the
# sign-in is kept in the profile).
if pgrep -f -- "--user-data-dir=$profile" > /dev/null; then
	pkill -f -- "--user-data-dir=$profile"

	for _ in $(seq 1 20); do
		pgrep -f -- "--user-data-dir=$profile" > /dev/null || break

		sleep 0.25
	done
fi

# Chrome reads its bookmarks when it starts, and the profile is the demo's
# alone, so they are written while it is not running: the bookmarks bar holds
# the demo's screens, and is shown.
if ! pgrep -f -- "--user-data-dir=$profile" > /dev/null; then
	mkdir -p "$profile/Default"

	printf '%s\n' "${bookmarks[@]}" |
		jq -R -n '
			[inputs | split("|") | {name: .[0], type: "url", url: (.[2:] | join("|"))}] as $bar |
			{
				roots: {
					bookmark_bar: {children: $bar, name: "Bookmarks bar", type: "folder"},
					other: {children: [], name: "Other bookmarks", type: "folder"},
					synced: {children: [], name: "Mobile bookmarks", type: "folder"}
				},
				version: 1
			}' > "$profile/Default/Bookmarks"

	preferences="$profile/Default/Preferences"

	[ -s "$preferences" ] || echo '{}' > "$preferences"

	jq '.bookmark_bar.show_on_all_tabs = true' "$preferences" > "$preferences.new" && mv "$preferences.new" "$preferences"
fi

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
	--user-data-dir="$profile" \
	--window-position="$x,$y" \
	--window-size="$width,$height" \
	"${urls[@]}" > /dev/null 2>&1 &

if command -v wmctrl > /dev/null; then
	for _ in $(seq 1 40); do
		window=$(wmctrl -lx | awk -v profile="($profile)" 'index($0, profile) { print $1 }' | tail -1)

		if [ -n "$window" ]; then
			sleep 0.5

			read -r left right top bottom < <(extents "$window")

			wmctrl -i -r "$window" -e "0,$(( x - left )),$(( y - top )),$(( width + left + right )),$(( height + top + bottom ))"

			break
		fi

		sleep 0.25
	done
fi

echo "Bookmarks:"

for bookmark in "${bookmarks[@]}"; do
	IFS='|' read -r number title _ <<< "$bookmark"

	printf '  %s  %s\n' "$number" "$title"
done

echo
echo "Sign in as ${LIFERAY_AUTH%%:*}, then switch to dark mode with the moon button in the Product Menu."
