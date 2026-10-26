#!/usr/bin/env bash
#
# Opens the browser for the demo: a Chrome window filling the screen to the
# right of demo/terminal.sh's window, with one tab: the portal's sign-in. It
# also starts the hotel grid if it is not running.
#
#   demo/browser.sh         the sign-in
#   demo/browser.sh --all   one tab for every screen the demo shows, in order,
#                           each once
#
# Those screens are also on the bookmarks bar. The design library's own
# screens are not among them, as its URLs change every time it is created, so
# open it from the Design Libraries list.
#
# The layout is for the presentation screen, zoomed to the one you rehearse on
# (demo/layout.sh): the browser fills the screen below GNOME's top bar to the
# right of the demo terminal (DEMO_BROWSER_X, in presentation pixels; default:
# the terminal's right edge, or half the screen). DEMO_BROWSER_SCALE sets
# Chrome's zoom; by default, pages lay out at 1000 CSS pixels or more.
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

# The browser screen of every step that shows one, in order:
# NUMBER|LABEL|TITLE|URL. The number is the step's act and number on the
# terminal (a, b... when a step shows several screens); with the label it
# names the bookmark, and the titles are printed as a legend. The design
# library's own screens have no fixed URL (it is created anew in every run),
# so their bookmarks open the Design Libraries list.
# One bookmarks folder per act, short enough for all of them to fit on the
# bookmarks bar.
ACT_FOLDERS=(
	"0. Start"
	"1. Madrid"
	"2. London"
	"3. Move"
	"4. MCP"
	"5. Agent"
	"6. Cities"
	"7. Winter"
)

MADRID_ADMIN="$LIFERAY_URL/group/ray-s-hotel-madrid"
LONDON_ADMIN="$LIFERAY_URL/group/ray-s-hotel-london"
SITES="$LIFERAY_URL/group/control_panel/manage?p_p_id=com_liferay_site_admin_web_portlet_SiteAdminPortlet"
LIBRARIES="$LIFERAY_URL/group/control_panel/manage?p_p_id=com_liferay_design_library_web_internal_portlet_DesignLibraryAdminPortlet"
MCP_TOOLS_URL="$LIFERAY_URL/group/control_panel/manage?p_p_id=$MCP_PORTLET&p_p_lifecycle=0&p_p_state=maximized&_${MCP_PORTLET}_mvcRenderCommandName=%2Fmcp_server%2Fedit_profile&_${MCP_PORTLET}_profileERC=devcon&_${MCP_PORTLET}_tab=tools"

bookmarks=(
	"0.1|Sign in|Sign in|$LIFERAY_URL/c/portal/login"
	"1.1|Sites|Sites (Madrid appears)|$SITES"
	"1.2|Hotel set|Madrid: Ray’s Hotel fragments (the set appears)|$MADRID_ADMIN$FRAGMENTS=rays-hotel"
	"1.3|View image|Madrid: Ray’s Hotel resources (madrid-room.svg)|$MADRID_ADMIN$FRAGMENTS=rays-hotel$RESOURCES"
	"1.4|Ray image|Madrid: Ray’s Hotel resources (madrid-ray.png)|$MADRID_ADMIN$FRAGMENTS=rays-hotel$RESOURCES"
	"1.5|Header|Madrid: Ray’s Hotel fragments (Hotel Header)|$MADRID_ADMIN$FRAGMENTS=rays-hotel"
	"1.6|Campaigns|Madrid: Ray’s Campaigns fragments|$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	"1.7|Resources|Madrid: Ray’s Campaigns resources (the images folder)|$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES"
	"1.8|Images folder|Madrid: Ray’s Campaigns resources, then open the images folder|$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES"
	"1.9|Offer|Madrid: Ray’s Campaigns fragments (Seasonal Offer)|$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	"1.10a|Pages|Madrid: pages (before and after the request)|$MADRID_ADMIN$PAGES"
	"1.10b|Madrid hotel|Madrid hotel page|$LIFERAY_URL/web/ray-s-hotel-madrid/hotel-home"
	"2.1a|Sites|Sites (London appears)|$SITES"
	"2.1b|London header|London: Ray’s Hotel fragments (London's Hotel Header)|$LONDON_ADMIN$FRAGMENTS=rays-hotel"
	"2.2|Libraries|Design Libraries (Ray’s Design Library appears)|$LIBRARIES"
	"2.3|Connect Madrid|Design Libraries > Ray’s Design Library: Connected Sites (before and after)|$LIBRARIES"
	"2.4|Connect London|Design Libraries > Ray’s Design Library: Connected Sites|$LIBRARIES"
	"3.2|Library set|Design Libraries > Ray’s Design Library (empty), then its Ray’s Campaigns|$LIBRARIES"
	"3.4|Resources|Design Libraries > Ray’s Design Library > Ray’s Campaigns > Resources|$LIBRARIES"
	"3.6|Images|Design Libraries > Ray’s Design Library > Ray’s Campaigns > Resources > images|$LIBRARIES"
	"3.8|Fragments|Design Libraries > Ray’s Design Library > Ray’s Campaigns fragments|$LIBRARIES"
	"3.9|Madrid hotel|Madrid hotel page|$LIFERAY_URL/web/ray-s-hotel-madrid/hotel-home"
	"3.10|Grid|Hotel grid: Madrid and London|$GRID_URL/?cities=Madrid,London"
	"3.11a|Set gone|Madrid: Ray’s Hotel fragments (Ray’s Campaigns is gone)|$MADRID_ADMIN$FRAGMENTS=rays-hotel"
	"3.11b|Grid|Hotel grid: Madrid and London|$GRID_URL/?cities=Madrid,London"
	"4.1|Profile|MCP Server: profiles (devcon appears)|$LIFERAY_URL/group/control_panel/manage?p_p_id=$MCP_PORTLET"
	"4.2|Tools|MCP Server: the devcon profile's tools|$MCP_TOOLS_URL"
	"5.3|Breakfast Hours|Design Libraries > Ray’s Design Library > Ray’s Campaigns fragments (Breakfast Hours)|$LIBRARIES"
	"5.4|Thumbnail|Design Libraries > Ray’s Design Library > Ray’s Campaigns: Breakfast Hours with its thumbnail, then open it|$LIBRARIES"
	"5.6|Grid|Hotel grid: Madrid and London (with Breakfast Hours)|$GRID_URL/?cities=Madrid,London"
	"6.1|All hotels|Hotel grid: all eight hotels (they appear as they open)|$GRID_URL/"
	"7.2|Autumn|Hotel grid: all eight hotels (still autumn)|$GRID_URL/"
	"7.3a|Propagate|Design Libraries > Ray’s Design Library > Ray’s Campaigns: Seasonal Offer > View Site Usages > select all > Propagate|$LIBRARIES"
	"7.3b|Winter|Hotel grid: all eight hotels (winter)|$GRID_URL/"
)

urls=("$LIFERAY_URL/c/portal/login")

if [ "${1:-}" = --all ]; then
	urls=()

	for bookmark in "${bookmarks[@]}"; do
		url="${bookmark#*|*|*|}"

		[[ " ${urls[*]} " == *" $url "* ]] || urls+=("$url")
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
		jq -R -n --argjson folders "$(printf '%s\n' "${ACT_FOLDERS[@]}" | jq -R -s 'split("\n") | map(select(. != ""))')" '
			[inputs | split("|") | {act: (.[0] | split(".")[0] | tonumber), name: "\(.[0]) \(.[1])", type: "url", url: (.[3:] | join("|"))}] |
			group_by(.act) |
			map({children: map(del(.act)), name: $folders[.[0].act], type: "folder"}) as $bar |
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

	jq '.bookmark_bar.show_on_all_tabs = true | .bookmark_bar.show_apps_shortcut = false | .bookmark_bar.show_tab_groups = false' "$preferences" > "$preferences.new" && mv "$preferences.new" "$preferences"
fi

if [ -z "$CHROME" ]; then
	echo "Chrome or Chromium not found. Set CHROME to its path."

	exit 1
fi

if ! curl -s -o /dev/null "$GRID_URL/"; then
	setsid "$ROOT_DIR/demo/hotel-grid.py" > "$HOME/.cache/devcon-hotel-grid.log" 2>&1 &

	for _ in $(seq 1 20); do
		curl -s -o /dev/null "$GRID_URL/" && break

		sleep 0.5
	done
fi

source "$ROOT_DIR/demo/layout.sh"

# A window's X geometry includes the shadow it draws around itself
# (_GTK_FRAME_EXTENTS: left, right, top, bottom), so this works with the
# visible frames: the browser's starts where the terminal's ends.
extents() {
	xprop -id "$1" _GTK_FRAME_EXTENTS 2> /dev/null | tr -d ',' | awk '{ print ($3 == "" ? 0 : $3), ($4 == "" ? 0 : $4), ($5 == "" ? 0 : $5), ($6 == "" ? 0 : $6) }'
}

terminal_right=""
terminal=$(wmctrl -l 2> /dev/null | awk '/Ray’s Hotels demo/ { print $1 }' | tail -1)

if [ -n "$terminal" ]; then
	read -r terminal_x terminal_width < <(xdotool getwindowgeometry "$((terminal))" | awk '/Position/ { split($2, p, ","); x = p[1] } /Geometry/ { split($2, s, "x"); print x, s[1] }')
	read -r _ terminal_shadow_right _ _ < <(extents "$terminal")

	terminal_right=$(( terminal_x + terminal_width - terminal_shadow_right ))
fi

if [ -n "${DEMO_BROWSER_X:-}" ]; then
	x=$(px "$DEMO_BROWSER_X")
else
	x="${terminal_right:-$(px $(( SCREEN_WIDTH / 2 )))}"
fi

y="$TOP"
width=$(( $(px "$SCREEN_WIDTH") - x ))
height=$(px $(( SCREEN_HEIGHT - DEMO_TOP_BAR )))

# Pages lay out at no less than 1000 CSS pixels, as in the video: the
# fragments admin needs 992 to show the fragment sets beside their fragments.
# The zoom keeps them at the same CSS width on a bigger screen.
scale="${DEMO_BROWSER_SCALE:-$(awk -v width="$width" -v zoom="$ZOOM" 'BEGIN { css = width / zoom; print (css < 1000 ? css / 1000 : 1) * zoom }')}"

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
	IFS='|' read -r number label title _ <<< "$bookmark"

	printf '  %-5s %-15s %s\n' "$number" "$label" "$title"
done

echo
echo "Sign in as ${LIFERAY_AUTH%%:*}, then switch to dark mode with the moon button in the Product Menu."
