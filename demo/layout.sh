# Sourced by demo/terminal.sh and demo/browser.sh. The windows are laid out
# for the presentation screen, DEMO_SCREEN (default 1920x1080 at 100%, like
# the slides), with GNOME's top bar taking its first DEMO_TOP_BAR pixels
# (default 32). On another screen the whole layout is zoomed to fit it
# (DEMO_ZOOM, by default the screen's size over DEMO_SCREEN's), fonts and
# browser zoom included, so a rehearsal on a bigger screen shows the same
# columns, rows and page widths as the presentation, only bigger.

DEMO_SCREEN="${DEMO_SCREEN:-1920x1080}"
DEMO_TOP_BAR="${DEMO_TOP_BAR:-32}"

SCREEN_WIDTH="${DEMO_SCREEN%x*}"
SCREEN_HEIGHT="${DEMO_SCREEN#*x}"

read -r actual_width actual_height < <(xdotool getdisplaygeometry 2> /dev/null || echo "$SCREEN_WIDTH $SCREEN_HEIGHT")

ZOOM="${DEMO_ZOOM:-$(awk -v aw="$actual_width" -v ah="$actual_height" -v w="$SCREEN_WIDTH" -v h="$SCREEN_HEIGHT" 'BEGIN { z = aw / w; if (ah / h < z) z = ah / h; print z }')}"

# X fonts and GTK windows are scaled by Xft.dpi (192 on a 200% screen): font
# sizes in points are divided by it, so the zoom is not applied twice.
DPI_SCALE=$(xrdb -query 2> /dev/null | awk '/^Xft.dpi:/ { print $2 / 96; found = 1 } END { if (!found) print 1 }')

# The top of the area below GNOME's top bar on this screen.
TOP=$(xprop -root _NET_WORKAREA 2> /dev/null | tr -d ',' | awk '{ print $4 }')
TOP="${TOP:-$(awk -v n="$DEMO_TOP_BAR" -v z="$ZOOM" 'BEGIN { printf "%d", n * z + 0.5 }')}"

# px N: N presentation pixels on this screen.
px() {
	awk -v n="$1" -v z="$ZOOM" 'BEGIN { printf "%d", n * z + 0.5 }'
}
