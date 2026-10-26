#!/usr/bin/env bash
#
# Opens both windows of the demo, side by side: the terminal on the left
# (demo/terminal.sh) and the browser filling the rest of the screen
# (demo/browser.sh), which also starts the hotel grid.
#
#   demo/windows.sh             a shell, ready for ./demo.sh
#   demo/windows.sh ./demo.sh   the demo, straight away
#
# Both scripts' variables apply (DEMO_SCREEN, DEMO_FONT_SIZE, ...).

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

"$DIR/terminal.sh" "$@"
"$DIR/browser.sh"
