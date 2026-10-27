#!/usr/bin/env bash
#
# Closes the demo, whatever of it is open: a running ./demo.sh and its
# browser driver, the demo terminal (demo/terminal.sh), the demo browser
# (demo/browser.sh) and the hotel grid (demo/hotel-grid.py). Your usual
# terminal and browser are not touched.
#
#   demo/close.sh             close them
#   demo/close.sh --dry-run   only say what would be closed

set -uo pipefail

DRY_RUN=""

[ "${1:-}" = --dry-run ] && DRY_RUN=1

closed=0

# stop DESCRIPTION PID...: ends the processes, politely first.
stop() {
	local description="$1"

	shift

	[ $# -eq 0 ] && return

	closed=$((closed + 1))

	if [ -n "$DRY_RUN" ]; then
		echo "Would close $description"

		return
	fi

	echo "Closing $description"

	kill "$@" 2> /dev/null

	for _ in $(seq 1 20); do
		kill -0 "$@" 2> /dev/null || return

		sleep 0.25
	done

	kill -9 "$@" 2> /dev/null
}

# pids_with_env TEXT COMMAND: the processes running COMMAND whose
# environment contains TEXT.
pids_with_env() {
	local pid

	for pid in $(pgrep -x "$2"); do
		grep -qaF "$1" "/proc/$pid/environ" 2> /dev/null && echo "$pid"
	done
}

stop "the running demo (./demo.sh)" $(pgrep -f '^(/usr/bin/)?bash (\S*/)?demo\.sh( |$)')
stop "the browser driver" $(pgrep -f 'node \S*demo/browser-driver\.mjs')
stop "the demo terminal" $(pids_with_env devcon-demo-terminal ptyxis)
stop "the demo browser" $(pgrep -f -- "--user-data-dir=$HOME/\.cache/devcon-demo-browser( |$)" | head -1)
stop "the hotel grid" $(pgrep -f 'python3 \S*demo/hotel-grid\.py')

[ $closed -eq 0 ] && echo "Nothing of the demo is open."

exit 0
