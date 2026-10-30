#!/usr/bin/env bash
#
# One API, Thousands of Sites: step-by-step demo
#
#   ./demo.sh            run every act, pausing before each request
#   ./demo.sh act3       run a single act (act1 ... act7)
#   ./demo.sh resume     go on from the first step not done yet, after the
#                        demo stopped (from the beginning if nothing is done)
#   ./demo.sh offline, ./demo.sh resume offline, ./demo.sh act5 offline...
#                        any of these, with act 5 using the cached agent run
#                        (AI_FALLBACK=1), when the agent or the network fails
#   ./demo.sh resume fix the same, after rebuilding the portal: it clears what
#                        the demo created and runs every step done again,
#                        without showing it (the agent from its cached run),
#                        for when the portal lost or broke the demo's data
#   ./demo.sh video      play the demo video fullscreen, from the start: the
#                        newest devcon-demo*.mp4 (with its .acts file) in
#                        ~/tmp or the downloads folder, or DEMO_VIDEO
#   ./demo.sh resume video
#                        the same, from the step the demo stopped at (from
#                        the start if nothing is done)
#   ./demo.sh from act5  run from the start of an act to the end
#   ./demo.sh reset      back to the starting point: no hotels yet
#   ./demo.sh help       this help, every act's steps, and where resume goes on
#
# NO_PAUSE=1 ./demo.sh   run without waiting for key presses
# AI_FALLBACK=1 ./demo.sh act5
#                        create the Breakfast Hours fragment from the cached agent
#                        run instead of launching Claude Code
# DEMO_BROWSER=0 ./demo.sh
#                        leave the browser alone (the bookmarks have every
#                        screen)
# DEMO_BROWSER_DELAY=1.5 ./demo.sh
#                        seconds the browser waits after the terminal before
#                        it changes (default 1)
# DEMO_CDP_PORT=9333     the demo browser's remote control port (default 9333)
#
# Keys, at any prompt:
#   any key, Page Down   go on (Page Down is a clicker's "next")
#   ← or Page Up         show the screen before, as it was, without running it
#   →                    the screen after, back to the current one
#
# Each screen shows the act's use case, the steps so far (the current one
# highlighted) and one API call. The browser follows: each step shows its
# screen there (demo/browser.sh starts it with its remote control), and the
# "UI:" comments say which.
#

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

source "$DIR/lib.sh"

LIBRARY="$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC"
MADRID="$FRAGMENT_API/sites/$MADRID_ERC"
LONDON="$FRAGMENT_API/sites/$LONDON_ERC"
ASSET_LIBRARY_API="$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries"

B=$'\033[1m'
DIM=$'\033[2m'
R=$'\033[0m'

ACT=""
ACT_NUMBER=0
ACT_TEXT=""
STEP=""
STEPS=()

# What the demo has done, for ./demo.sh resume: STATE_DIR/done lists the
# steps done (ACT.STEP), and STATE_DIR/ACT.STEP.json keeps each step's
# response, so the steps skipped on resume leave LAST as it was.
STATE_DIR="$HOME/.cache/devcon-demo-state"
RESUMING=""
REPLAYING=""
SKIPPING=""
CURRENT=""

exec 3>&1

# The acts' short names on the progress bar, the same as the browser's
# bookmark folders.
ACT_NAMES=(Madrid "Shared fragments" London MCP Agent Cities "Early bird")

# compact: a terminal with fewer than 40 rows, where the screens skip their
# blank lines.
compact() {
	[ "$(rows)" -lt 40 ]
}

cols() {
	tput cols 2> /dev/null < /dev/tty || echo 80
}

rows() {
	tput lines 2> /dev/null < /dev/tty || echo 30
}

# marker NAME VALUE: an invisible marker the video recorder follows.
marker() {
	printf '\033]1337;devcon-%s=%s\007' "$1" "$2"
}

# act TITLE TEXT, called from actN. Each sentence of TEXT starts a line.
act() {
	step_done
	ACT="$1"
	ACT_NUMBER="${FUNCNAME[1]#act}"
	ACT_TEXT="${2//. /.$'\n'}"
	STEPS=()

	if [ -n "$RESUMING" ]; then
		skip_if_done "$ACT_NUMBER.1"
	else
		forget_from "$ACT_NUMBER"
	fi

	marker act "$ACT"

	# The act's title and story first, on their own, until a key is pressed.
	if [ -z "$SKIPPING" ]; then
		header
		wait_key "start"
	fi
}

# step_count N: the number of steps of act N.
step_count() {
	declare -f "act$1" | grep -cE '^\s*step '
}

# progress: every act's steps as dots, with the names of the acts that have
# started above them.
progress() {
	local a i n color names=" " dots=" " width

	for ((a = 1; a <= ${#ACT_NAMES[@]}; a++)); do
		n=$(step_count "$a")
		width=$((n + 2))
		[ ${#ACT_NAMES[a - 1]} -gt $width ] && width=${#ACT_NAMES[a - 1]}

		if [ "$a" -lt "$ACT_NUMBER" ]; then
			color=$'\033[32m'
		elif [ "$a" -eq "$ACT_NUMBER" ]; then
			color=$'\033[1;33m'
		else
			color=$DIM
		fi

		if [ "$a" -le "$ACT_NUMBER" ]; then
			names+="$color$(printf "%-${width}s" "${ACT_NAMES[a - 1]}")$R  "
		else
			names+="$(printf "%-${width}s" "")  "
		fi

		dots+="$color$a$R "

		for ((i = 1; i <= n; i++)); do
			if [ "$a" -lt "$ACT_NUMBER" ] || { [ "$a" -eq "$ACT_NUMBER" ] && [ $i -lt ${#STEPS[@]} ]; }; then
				dots+=$'\033[32m●'
			elif [ "$a" -eq "$ACT_NUMBER" ] && [ $i -eq ${#STEPS[@]} ]; then
				dots+=$'\033[1;33m◉'
			else
				dots+="$R$DIM○"
			fi
		done

		dots+="$R$(printf "%$((width - n - 2))s" "")  "
	done

	printf '%s\n%s\n' "${names%"${names##*[! ]}"}" "${dots%"${dots##*[! ]}"}"
}

header() {
	local width i n

	width=$(cols)

	SCREEN_START=$(log_size)

	printf '\033[2J\033[3J\033[H'
	progress
	printf '\033[1;97;44m %-*s\033[0m\n' "$((width - 1))" "Ray’s Hotels · $ACT_NUMBER. $ACT"
	fold -s -w "$((width - 2))" <<< "$ACT_TEXT" | sed "s/^/ ${B}/; s/\$/${R}/"
	compact || printf '\n'

	n=${#STEPS[@]}
	i=0

	if [ $n -gt 3 ]; then
		printf ' \033[32m✓\033[0m %s%d.1–%d.%d%s\n' "$DIM" "$ACT_NUMBER" "$ACT_NUMBER" "$((n - 1))" "$R"
		i=$((n - 1))
	fi

	for (( ; i < n; i++)); do
		if [ $i -eq $((n - 1)) ]; then
			printf ' \033[1;33m▶ %d.%d %s\033[0m\n' "$ACT_NUMBER" "$((i + 1))" "${STEPS[$i]}"
		else
			printf ' \033[32m✓\033[0m %s%d.%d %s%s\n' "$DIM" "$ACT_NUMBER" "$((i + 1))" "${STEPS[$i]}" "$R"
		fi
	done

	printf '%s%s%s\n' "$DIM" "$(printf '─%.0s' $(seq 1 "$width"))" "$R"
}

# step ID TEXT: a new step, on a clean screen, or skipped when resuming and
# done already.
step() {
	step_done
	BROWSER_RELOAD=""
	BROWSER_AFTER=""
	STEP="$1"
	STEPS+=("$2")
	CURRENT="$ACT_NUMBER.${#STEPS[@]}"

	[ -n "$RESUMING" ] && skip_if_done "$CURRENT"

	marker step "$STEP"

	header
}

# step_done: the step on screen is done once the demo moves past it.
step_done() {
	[ -z "$CURRENT" ] || [ -n "$SKIPPING" ] && return

	grep -qxF "$CURRENT" "$STATE_DIR/done" 2> /dev/null || echo "$CURRENT" >> "$STATE_DIR/done"
}

# skip_if_done KEY: skips, with no output, while the steps are done already;
# shows the screen again from the first one that is not.
skip_if_done() {
	if grep -qxF "$1" "$STATE_DIR/done" 2> /dev/null || { [ -n "$REPLAYING" ] && not_after "$1" "$REPLAYING"; }; then
		SKIPPING=1
		exec > /dev/null
	else
		SKIPPING=""
		RESUMING=""
		exec >&3
	fi
}

# not_after A.S B.S: true when step A.S comes before or is B.S.
not_after() {
	[ "${1%%.*}" -lt "${2%%.*}" ] || { [ "${1%%.*}" -eq "${2%%.*}" ] && [ "${1#*.}" -le "${2#*.}" ]; }
}

# forget_from ACT: a new run of an act forgets it and the acts after it.
forget_from() {
	mkdir -p "$STATE_DIR"
	touch "$STATE_DIR/done"
	awk -F. -v act="$1" '$1 < act' "$STATE_DIR/done" > "$STATE_DIR/done.new"
	mv "$STATE_DIR/done.new" "$STATE_DIR/done"
}

# live: true unless the step is being skipped.
# live: true unless the step is being skipped, or when it is being replayed
# (./demo.sh resume fix).
live() {
	[ -z "$SKIPPING" ] || [ -n "$REPLAYING" ]
}

say() {
	fold -s -w "$(($(cols) - 2))" <<< "$*" | sed 's/^/ /'
}

note() {
	fold -s -w "$(($(cols) - 2))" <<< "$*" | sed "s/^/ ${DIM}/; s/\$/${R}/"
}

# Every screen the demo shows is also written to SCREEN_LOG. Each key press
# keeps where the screen on display starts and ends in it, so the left and
# right arrow keys can show the earlier screens again, as they were, without
# running anything. A presentation clicker sends Page Up and Page Down: Page
# Up goes back like ←, and Page Down goes forward like →, or on to the next
# step from the current screen, like any other key.
SCREEN_LOG=""
SCREEN_START=0
SNAP_START=()
SNAP_END=()

# log_screens: from here on, the output also goes to SCREEN_LOG.
log_screens() {
	SCREEN_LOG=$(mktemp)

	exec > >(tee -a "$SCREEN_LOG")
	exec 3>&1
}

# log_size: the size of SCREEN_LOG, once tee has written everything so far.
log_size() {
	local before now

	[ -n "$SCREEN_LOG" ] || { echo 0; return; }

	now=$(stat -c %s "$SCREEN_LOG")

	for _ in 1 2 3 4 5 6 7 8 9 10; do
		before=$now
		sleep 0.02
		now=$(stat -c %s "$SCREEN_LOG")
		[ "$now" = "$before" ] && break
	done

	echo "$now"
}

# replay N [NOTE]: shows the Nth screen kept, straight on the terminal.
replay() {
	{
		printf '\033[2J\033[3J\033[H'
		tail -c +$(( SNAP_START[$1] + 1 )) "$SCREEN_LOG" | head -c $(( SNAP_END[$1] - SNAP_START[$1] ))
		[ -n "${2:-}" ] && printf '\n%s[ %s ]%s' "$DIM" "$2" "$R"
	} > /dev/tty
}

wait_key() {
	[ -n "${NO_PAUSE:-}" ] || [ -n "$SKIPPING" ] && return

	local i key live rest prompt

	prompt=$(printf '\n%s[ press any key to %s ]%s' "$DIM" "$1" "$R")

	if [ -n "$SCREEN_LOG" ]; then
		SNAP_START+=("$SCREEN_START")
		SNAP_END+=("$(log_size)")
	fi

	printf '%s' "$prompt"

	live=$(( ${#SNAP_END[@]} - 1 ))
	i=$live

	while :; do
		read -rsn1 key < /dev/tty || continue

		if [ "$key" = $'\e' ]; then
			while read -rsn1 -t 0.02 rest < /dev/tty; do
				key+="$rest"
			done
		fi

		case "$key" in
			$'\e[D' | $'\e[5~')
				if [ "$i" -gt 0 ]; then
					i=$(( i - 1 ))
					replay "$i" "an earlier screen · ← → to browse · any other key: back to now"
				fi
				;;
			$'\e[C' | $'\e[6~')
				if [ "$i" -lt "$live" ]; then
					i=$(( i + 1 ))

					if [ "$i" -eq "$live" ]; then
						replay "$i"
						printf '%s' "$prompt" > /dev/tty
					else
						replay "$i" "an earlier screen · ← → to browse · any other key: back to now"
					fi
				elif [ "$key" = $'\e[6~' ]; then
					break
				fi
				;;
			*)
				[ "$i" -eq "$live" ] && break

				i=$live
				replay "$i"
				printf '%s' "$prompt" > /dev/tty
				;;
		esac
	done

	printf '\r\033[K\033[1A\033[K'
}

PATH_COLOR=$'\033[1;37m'
ERC_COLOR=$'\033[1;38;5;214m'

# Collections whose next path segment is an external reference code.
ERC_COLLECTIONS=" asset-libraries by-external-reference-code connected-sites design-libraries fragment-sets fragments resource-folders resource-files site-pages sites "

# show_path METHOD PATH: the endpoint, wrapped after a slash, continuation
# lines indented, with external reference codes in their own color.
show_path() {
	local method="$1" path="$2" width indent plain="" colored="" part previous="" first=1 limit query=""
	local parts=()

	width=$(($(cols) - 2))
	indent=$((${#method} + 4))

	if [[ "$path" == *"?"* ]]; then
		query="?${path#*\?}"
		path="${path%%\?*}"
	fi

	IFS='/' read -ra parts <<< "${path#/}"

	printf ' \033[1;33m%s\033[0m ' "$method"

	plain="/"
	colored="${PATH_COLOR}/"

	for part in "${parts[@]}"; do
		limit=$((first ? width - ${#method} - 1 : width - indent))

		if [ "$plain" != "/" ] && [ -n "$plain" ] && [ $((${#plain} + ${#part} + 1)) -gt "$limit" ]; then
			[ $first -eq 1 ] || printf '%*s' "$indent" ''
			printf '%s%s\n' "$colored" "$R"

			first=0
			plain=""
			colored="$PATH_COLOR"
		fi

		if [[ "$ERC_COLLECTIONS" == *" $previous "* ]] || { [ "$previous" = mcp ] && [ "$part" = "${parts[-1]}" ]; }; then
			colored="$colored$ERC_COLOR$part$PATH_COLOR/"
		else
			colored="$colored$part/"
		fi

		plain="$plain$part/"
		previous="$part"
	done

	colored="${colored%/}"

	if [ -n "$query" ]; then
		if [ $((${#plain} + ${#query})) -gt "$((first ? width - ${#method} - 1 : width - indent))" ]; then
			[ $first -eq 1 ] || printf '%*s' "$indent" ''
			printf '%s%s\n' "$colored" "$R"

			first=0
			colored="$PATH_COLOR"
		fi

		colored="$colored$query"
	fi

	[ $first -eq 1 ] || printf '%*s' "$indent" ''
	printf '%s%s\n' "$colored" "$R"
}

# show_json JSON FILTER MAX_LINES: pretty JSON whose lines never wrap.
show_json() {
	local width

	width=$(($(cols) - 3))

	jq --argjson max "$((width - 30))" "($2) | walk(if type == \"string\" and length > \$max then .[0:\$max] + \"…\" else . end)" <<< "$1" 2> /dev/null |
		awk -v width="$width" -v max="$3" '
			NR > max { cut = 1; next }
			{ if (length($0) > width) $0 = substr($0, 1, width - 1) "…"; print " " $0 }
			END { if (cut) print " …" }'
}

colorize() {
	sed -E "s/(\"[^\"]*\")(:)/\x1b[38;5;117m\1\x1b[0m\2/g; s/: (\"[^\"]*\"?)([,}]|$)/: \x1b[32m\1\x1b[0m\2/g"
}

# highlight: in the lines that match HIGHLIGHT (an extended regular
# expression), the values that match it, alone or with their key, turn
# yellow, so the audience knows where to look.
highlight() {
	HIGHLIGHT="${HIGHLIGHT:-}" perl -CSD -ne '
		BEGIN { $h = $ENV{HIGHLIGHT} }
		chomp;
		(my $plain = $_) =~ s/\e\[[0-9;]*m//g;
		if ($h eq "" || $plain !~ /$h/) { print "$_\n"; next }
		$plain =~ s{("(?:[^"\\]|\\.)*")(\s*:\s*)?("(?:[^"\\]|\\.)*"?|-?[\w.]+)?}{
			my ($k, $colon, $v) = ($1, $2, $3);
			if (defined $colon) {
				"\e[38;5;117m$k\e[0m$colon" . (defined $v ? ("$k$colon$v" =~ /$h/ ? "\e[1;33m$v\e[0m" : $v =~ /^"/ ? "\e[32m$v\e[0m" : $v) : "")
			} else {
				($k =~ /$h/ ? "\e[1;33m$k\e[0m" : $k) . ($v // "")
			}
		}ge;
		print "$plain\n";
	'
}

LAST=""

# request METHOD URL [BODY] [RESPONSE_FILTER] [BODY_FILTER]
request() {
	local method="$1" url="$2" body="${3:-}" filter="${4:-.}" body_filter="${5:-.}"

	show_path "$method" "${url#$LIFERAY_URL}"

	local used

	used=$(( (${#STEPS[@]} > 3 ? 2 : ${#STEPS[@]}) + $(fold -s -w "$(($(cols) - 2))" <<< "$ACT_TEXT" | wc -l) + 14))

	compact && used=$((used - 4))

	if [ -n "$body" ] && [[ "$body_filter" == @* ]]; then
		jq -r "${body_filter#@}" <<< "$body" | sed 's/^/ /' | colorize | highlight
	elif [ -n "$body" ]; then
		show_json "$body" "$body_filter" "$(($(rows) - used - 4))" | colorize | highlight
	fi

	wait_key "send the request"

	if [ -n "$SKIPPING" ] && [ -z "$REPLAYING" ]; then
		LAST=$(cat "$STATE_DIR/$CURRENT.json" 2> /dev/null)

		return
	fi

	local args=(--silent --write-out '\n%{http_code}' --user "$LIFERAY_AUTH" --request "$method" --header 'Accept: application/json, text/event-stream')
	local body_file=""

	if [ -n "$body" ]; then
		body_file=$(mktemp)
		printf '%s' "$body" > "$body_file"
		args+=(--header 'Content-Type: application/json' --data-binary "@$body_file")
	elif [ "$method" = POST ] || [ "$method" = PUT ]; then
		args+=(--header 'Content-Type: application/json' --data-binary '{}')
	fi

	local start output

	start=$(date +%s%N)
	output=$(curl "${args[@]}" "$url")

	[ -n "$body_file" ] && rm -f "$body_file"

	local elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
	local status="${output##*$'\n'}"

	LAST="${output%$'\n'*}"

	mkdir -p "$STATE_DIR"
	printf '%s' "$LAST" > "$STATE_DIR/$CURRENT.json"
	echo "$CURRENT" >> "$STATE_DIR/done"

	compact || printf '\n'

	if [[ "$status" == 2* ]]; then
		printf ' \033[1;32m← %s OK\033[0m %s(%s ms)%s\n' "$status" "$DIM" "$elapsed" "$R"
	else
		printf ' \033[1;31m← %s\033[0m %s(%s ms)%s\n' "$status" "$DIM" "$elapsed" "$R"
	fi

	marker done "$STEP"

	[ "$method" != GET ] && refresh

	[ -z "$LAST" ] || [ "$filter" = - ] && return

	local shown

	if [[ "$filter" == @* ]]; then
		shown=$(jq -r "${filter#@}" <<< "$LAST" 2> /dev/null | sed 's/^/ /')
	else
		shown=$(show_json "$LAST" "$filter" 14)
	fi

	if [ -n "$shown" ]; then
		colorize <<< "$shown" | highlight
	else
		printf '%s\n' "$LAST" | head -5
	fi
}

# next: the step's last key press, once the browser has shown all it had to
# for the step, so the terminal never moves on before the browser.
next() {
	browser_sync
	wait_key "continue"
}

# The browser follows the demo through demo/browser-driver.mjs, when the demo
# browser runs with its remote control (demo/browser.sh) and DEMO_BROWSER is
# not 0. show URL shows a screen when a step starts and reloads it once the
# step's request has changed something; show_still shows one that needs no
# reload (the hotel grid reloads its own tiles); show_after shows a second
# screen a couple of seconds after that reload, such as the page just created
# after the list of pages, and keeps it on screen for a few seconds before
# the step offers to continue. The design library's screens need its id, which
# changes in every run: library_urls looks it up.
BROWSER_RELOAD=""
BROWSER_AFTER=""
LIBRARY_ID=""
LIBRARY_VIEW=""
LIBRARY_SET=""

browser_on() {
	[ "${DEMO_BROWSER:-1}" != 0 ] && [ -z "$SKIPPING" ] || return 1

	if [ -z "${DRIVER_PID:-}" ]; then
		if ! curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${DEMO_CDP_PORT:-9333}/json/version"; then
			DEMO_BROWSER=0

			return 1
		fi

		coproc DRIVER { node "$DIR/demo/browser-driver.mjs" 2> /dev/null; }
	fi
}

browser() {
	browser_on && printf '%s\n' "$*" >&"${DRIVER[1]}"
}

browser_sync() {
	[ -z "${NO_PAUSE:-}" ] && browser_on || return 0

	printf 'sync\n' >&"${DRIVER[1]}"
	read -r -t 20 _ <&"${DRIVER[0]}"
}

show() {
	browser goto "$1"
	BROWSER_RELOAD=1
}

show_still() {
	browser goto "$1"
	BROWSER_RELOAD=""
}

show_after() {
	BROWSER_AFTER="goto $1"
}

# click_after TEXT: like show_after, but clicks the link that reads TEXT.
click_after() {
	BROWSER_AFTER="click $1"
}

# reveal_after [TEXT]: like show_after, but scrolls the page until its last
# fragment is fully in view, or until the item that reads TEXT is in the middle
# of the screen.
reveal_after() {
	BROWSER_AFTER="reveal${1:+ $1}"
}

refresh() {
	[ -n "$BROWSER_RELOAD" ] && browser reload

	if [ -n "$BROWSER_AFTER" ]; then
		browser wait 2
		browser $BROWSER_AFTER
		browser wait 4
		BROWSER_AFTER=""
	fi
}

library_urls() {
	browser_on || return 0

	[ -n "$LIBRARY_ID" ] || LIBRARY_ID=$(api GET "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" 2> /dev/null | jq -r '.id // empty')

	LIBRARY_VIEW="$LIBRARIES&p_p_lifecycle=0&p_p_state=maximized&_${LIBRARY_PORTLET}_mvcRenderCommandName=%2Fdesign_library%2Fview_resources_design_library&_${LIBRARY_PORTLET}_designLibraryEntryId=$LIBRARY_ID"
	LIBRARY_SET="$LIFERAY_URL/group/asset-library-$LIBRARY_ID$FRAGMENTS=$FRAGMENT_SET_ERC"
}

# profile_body: the MCP profile as sent, with the start of its instructions
# wrapped to the screen, as raw lines for request.
profile_body() {
	printf '@def width: %d; ' "$(( $(cols) - 9 ))"
	cat << 'EOF'
def wrap($w): reduce (split(" ")[] | select(. != "")) as $word ([""];
	if .[-1] == "" then .[-1] = $word
	elif (.[-1] | length) + 1 + ($word | length) > $w then . + [$word]
	else .[-1] += " " + $word end);
([.instructions | split("\n\n")[] | gsub("\n"; " ") | wrap(width), [""]] | add | .[:11]) as $lines |
"{",
"  \"externalReferenceCode\": \"\(.externalReferenceCode)\",",
"  \"name\": \"\(.name)\",",
"  \"instructions\":",
($lines | to_entries[] | "    \u001b[32m" + (if .key == 0 then "\"" else " " end) + .value + "\u001b[0m"),
"     \u001b[32m…\"\u001b[0m,",
"  \"profileStatus\": \"\(.profileStatus)\"",
"}"
EOF
}

# The fragment the agent created, as the API returns it, cut down to what it
# shows: where it went, its HTML and CSS, and the settings it exposes.
BREAKFAST_RESPONSE='@
	def cut($n): if length > $n then .[0:$n] + "…" else . end;
	"{",
	"  \"externalReferenceCode\": \(.externalReferenceCode | tojson),",
	"  \"name\": \(.name | tojson),",
	"  \"fragmentSetExternalReferenceCode\": \(.fragmentSetExternalReferenceCode | tojson),",
	"  \"fragmentVersions\": [{",
	(.fragmentVersions[] | select(.status == "Approved") |
		"    \"status\": \(.status | tojson),",
		"    \"html\": \(.html | cut(44) | tojson),",
		"    \"css\": \(.css | cut(44) | tojson),",
		"    \"configuration\": {\"fieldSets\": [{\"fields\": [",
		([.configuration.fieldSets[]?.fields[]?] as $fields | $fields | to_entries[] |
			"      {\"name\": \(.value.name | tojson), \"type\": \(.value.type | tojson),",
			"       \"defaultValue\": \(.value.defaultValue | tojson | gsub(":"; ": "))}\(if .key < ($fields | length) - 1 then "," else "]}]}" end)")),
	"  }]",
	"}"'

FRAGMENT_BODY='{externalReferenceCode, name, fragmentVersions: [.fragmentVersions[] | {html, css} + ([.configuration.fieldSets[]?.fields[]?.name] | if length > 0 then {configuration: join(", ")} else {} end)], thumbnailURLReference}'
FRAGMENT_RESPONSE='{externalReferenceCode, name}'
# The page as the Pages API receives it, with the fragment content each page
# element also carries left out, so it fits on one screen.
PAGE_BODY='@
	def element($last):
		.pageElementDefinition.fragmentInstance.fragmentReference as $reference |
		.pageElementDefinition.fragmentInstance.fragmentConfigurationFieldValues as $values |
		["    {\"pageElementDefinition\": {\"fragmentInstance\": {"] +
		if $values.city then
			[
				"      \"fragmentConfigurationFieldValues\": {",
				"        \"city\": {\"type\": \"Text\", \"value\": \"\($values.city.value)\"}, …},"
			]
		else [] end +
		["      \"fragmentReference\": {"] +
		if $reference.scope then
			[
				"        \"externalReferenceCode\": \"\($reference.externalReferenceCode)\",",
				"        \"scope\": {\"externalReferenceCode\": \"\($reference.scope.externalReferenceCode)\"}}}}}"
			]
		else
			["        \"externalReferenceCode\": \"\($reference.externalReferenceCode)\"}}}}"]
		end |
		if $last then . else .[length - 1] += "," end;
	.pageSpecifications[0] as $specification |
	$specification.pageExperiences[0].pageElements as $elements |
	(
		[
			"{",
			" \"externalReferenceCode\": \"\(.externalReferenceCode)\",",
			" \"pageSpecifications\": [{",
			"  \"status\": \"\($specification.status)\",",
			"  \"pageExperiences\": [{",
			"   \"pageElements\": ["
		] +
		([range(0; $elements | length) as $i | $elements[$i] | element($i == ($elements | length) - 1)] | add) +
		[
			"   ]}]},",
			"  \"…and its draft, with the same elements\"]",
			"}"
		]
	)[]'
ITEMS='[.items[] | {externalReferenceCode, name}]'

# put_hotel_page SITE_ERC SCOPE:FRAGMENT_ERC...
put_hotel_page() {
	local site="$1"

	shift

	request PUT "$SITE_API/sites/$site/site-pages/hotel-home" "$(page_payload "$site" "$@")" - "$PAGE_BODY"

	note "(each element also carries its fragment’s HTML, CSS and configuration)"
}

hotels() {
	say ""
	say "${B}What the hotel pages show now:${R}"

	show_sites
}

act1() {
	act "Madrid opens" "Ray’s Hotels opens its first hotel, in Madrid. We build it all through the headless APIs: its site, its fragments and their images, and its home page."

	# UI: Applications Menu > Sites: Ray’s Hotel Madrid appears.
	step site "Create the Madrid site"
	show "$SITES"
	request PUT "$SITE_API/sites/$MADRID_ERC" "{\"externalReferenceCode\": \"$MADRID_ERC\", \"name\": \"Ray’s Hotel Madrid\"}" '{externalReferenceCode, name, friendlyUrlPath}'
	next

	# UI: Madrid > Design > Fragments: the Ray’s Hotel set appears.
	step set "Create the Ray’s Hotel fragment set"
	show "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request PUT "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" '{"name": "Ray’s Hotel"}' '{externalReferenceCode, name}'
	next

	# UI: Ray’s Hotel > Resources, the images folder: the three images appear.
	step images "Upload the images, in a resource folder"
	show "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES&demoOpenFolder=$RESOURCE_FOLDER_ERC"
	say "${B}A resource folder, then three images in it:${R}"
	image_calls "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" folder madrid-room.svg madrid-ray.png devcon-guest.svg
	wait_key "upload the images"
	say ""

	if live; then
		printf ' '
		api POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "{\"externalReferenceCode\": \"$RESOURCE_FOLDER_ERC\", \"name\": \"$RESOURCE_FOLDER_ERC\"}" > /dev/null && tick "$RESOURCE_FOLDER_ERC/" &&
			post_images "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" madrid-room.svg madrid-ray.png devcon-guest.svg
		printf '\n'
	fi

	refresh
	marker done images
	next

	# UI: Ray’s Hotel > Fragments: the Hotel Header, with its thumbnail; then it opens in the fragment editor.
	step header "Create the Hotel Header"
	click_after "Hotel Header"
	show "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(header_payload)" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
	next

	# UI: Ray’s Hotel > Fragments: Seasonal Offer appears, with its thumbnail.
	step offer "Create the Seasonal Offer fragment"
	show "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(fragment_payload devcon configuration.json)" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
	next

	# UI: before the request, Madrid > Site Builder > Pages: no pages yet.
	#   /group/<madrid>/~/control_panel/manage?p_p_id=com_liferay_layout_admin_web_portlet_GroupPagesPortlet
	# After it, the same list with Hotel Home, then the Madrid hotel page.
	#   /web/<madrid>/hotel-home
	step page "Create Madrid’s hotel page"
	show "$MADRID_ADMIN$PAGES"
	show_after "$MADRID_PAGE"
	HIGHLIGHT='"externalReferenceCode": "rays-' put_hotel_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "$MADRID_ERC:$OFFER_FRAGMENT_ERC"
	next
}

tick() {
	printf ' %s \033[32m✓\033[0m' "$1"
}

# post_images SET_URL FILE...: uploads the images of assets/ into the set's
# images folder, with a tick for each.
post_images() {
	local file set="$1"

	shift

	for file in "$@"; do
		api POST "$set/resource-files" "$(resource_payload "$DIR/assets/$file" "$RESOURCE_FOLDER_ERC")" > /dev/null && tick "$file" || { printf ' \033[31m✗\033[0m'; return 1; }
	done
}

# call METHOD URL [BODY]: one call of a step that makes several, shown like a
# request: its endpoint, then its body.
call() {
	show_path "$1" "${2#$LIFERAY_URL}"

	[ -n "${3:-}" ] && show_json "$3" . 20 | colorize

	return 0
}

# image_calls SET_URL FOLDER FILE...: the calls that upload FILEs into the
# images folder of the set at SET_URL, creating the folder first when FOLDER
# is not empty.
image_calls() {
	local set="$1" folder="$2" first="$3"

	shift 2

	[ -n "$folder" ] && call POST "$set/resource-folders" "{\"externalReferenceCode\": \"$RESOURCE_FOLDER_ERC\", \"name\": \"$RESOURCE_FOLDER_ERC\"}" && printf '\n'

	call POST "$set/resource-files" "$(resource_payload "$DIR/assets/$first" "$RESOURCE_FOLDER_ERC")"

	shift

	[ $# -gt 0 ] && note "…and the same for $(sed -E 's/ ([^ ]+)$/ and \1/' <<< "$*")"

	return 0
}

act2() {
	act "Shared fragments" "Ray wants more hotels, all sharing the same fragments. We create a design library, connect Madrid, and move its fragments. No move operation: we copy, repoint the page and delete the originals."

	# UI: Applications Menu > Design Libraries: Ray’s Design Library appears.
	#   /group/control_panel/manage?p_p_id=com_liferay_design_library_web_internal_portlet_DesignLibraryAdminPortlet
	step library "Create the design library"
	show "$LIBRARIES"
	HIGHLIGHT='"type"' request PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" "{\"externalReferenceCode\": \"$DESIGN_LIBRARY_ERC\", \"name\": \"Ray’s Design Library\", \"settings\": {}, \"type\": \"DesignLibrary\"}" '{externalReferenceCode, name, type}'
	next

	# UI: Design Libraries > Ray’s Design Library: its Connected Sites card, empty before the request, then with Madrid.
	step connect-madrid "Connect Madrid to the design library"
	library_urls
	show "$LIBRARY_VIEW"
	request PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/$MADRID_ERC" '{"searchable": true}' '{externalReferenceCode, name}'
	next

	step read-set "Read the fragment set from Madrid"
	show_still "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" "" '{externalReferenceCode, name}'
	local set="$LAST"
	next

	# UI: before the request, Design Libraries > Ray’s Design Library: no design resources yet.
	# After it, the library's fragment sets: Ray’s Hotel.
	step put-set "Create it in the design library"
	library_urls
	show "$LIBRARY_VIEW"
	show_after "$LIBRARY_SET"
	request PUT "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC" "$(jq -c '{name}' <<< "$set")" '{externalReferenceCode, name}'
	next

	step read-folders "Read its resource folders"
	show_still "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES"
	request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "" "$ITEMS"
	local folder

	folder=$(jq -c '.items[0] // {} | {externalReferenceCode, name}' <<< "$LAST")
	next

	# UI: the library's Ray’s Hotel > Resources tab: the images folder appears.
	step post-folder "Create the images folder in the library"
	library_urls
	show "$LIBRARY_SET$RESOURCES"
	request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "$folder" '{externalReferenceCode, name}'
	next

	step read-files "Read the images in it"
	show_still "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES&demoOpenFolder=$RESOURCE_FOLDER_ERC"
	request GET "$FRAGMENT_API/sites/$MADRID_ERC/resource-folders/$RESOURCE_FOLDER_ERC/resource-files?nestedFields=fileURLReference.fileBase64" "" '[.items[] | {externalReferenceCode, fileURLReference: {fileBase64: .fileURLReference.fileBase64}}]'
	local files="$LAST"
	next

	# UI: the library's Ray’s Hotel > Resources > images: the three images appear.
	step post-files "Copy the images to the library"
	library_urls
	show "$LIBRARY_SET$RESOURCES&demoOpenFolder=$RESOURCE_FOLDER_ERC"
	say "${B}Each image as it was read, into the library’s images folder:${R}"
	image_calls "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC" "" $(jq -r '.items[].name' <<< "$files" 2> /dev/null)
	wait_key "copy the images"
	say ""

	if live; then
		printf ' '

		local file

		while read -r file; do
			api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$file" > /dev/null && tick "$(jq -r .name <<< "$file")" || printf ' \033[31m✗\033[0m'
		done < <(jq -c --arg folder "$RESOURCE_FOLDER_ERC" '.items[] | {externalReferenceCode, fileURLReference: {fileBase64: .fileURLReference.fileBase64}, name, resourceFolderExternalReferenceCode: $folder}' <<< "$files")

		printf '\n'
	fi

	refresh
	marker done post-files
	next

	step read-fragments "Read its fragments"
	show_still "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "" "$ITEMS"
	local fragments="$LAST"
	next

	# UI: the library's Ray’s Hotel > Fragments: the Hotel Header, then Seasonal Offer, with their thumbnails.
	step post-fragments "Copy both fragments to the library"
	library_urls
	show "$LIBRARY_SET"
	note "(the Hotel Header, with its thumbnail; the offer follows the same way)"
	request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(library_fragment "$fragments" "$HEADER_FRAGMENT_ERC")" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"

	if live; then
		api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(library_fragment "$fragments" "$OFFER_FRAGMENT_ERC")" > /dev/null && tick "Seasonal Offer, the same way" || printf ' \033[31m✗\033[0m'
		printf '\n'
		browser reload
	fi

	next

	# UI: the Madrid hotel page, unchanged.
	step madrid-page "Point Madrid’s page to the library’s fragments"
	show "$MADRID_PAGE"
	HIGHLIGHT='rays-design-library' put_hotel_page "$MADRID_ERC" "library:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC"
	next

	# UI: Madrid > Design > Fragments: no fragment sets left. Then the Madrid hotel page, still the same.
	step delete-set "Delete the fragment set from Madrid"
	show "$MADRID_ADMIN$FRAGMENTS="
	show_after "$MADRID_PAGE"
	request DELETE "$MADRID/fragment-sets/$FRAGMENT_SET_ERC"
	hotels
	next
}

# library_fragment FRAGMENTS ERC: the fragment ERC of FRAGMENTS (a page of
# Madrid's fragments), with its thumbnail, as the library receives it.
library_fragment() {
	local thumbnail

	thumbnail=$(mktemp)

	thumbnail_file "$MADRID/fragments/$2" "$thumbnail" || : > "$thumbnail"

	jq -c --arg erc "$2" --rawfile thumbnail <(base64 -w0 "$thumbnail") '.items[] | select(.externalReferenceCode == $erc) | {externalReferenceCode, fragmentVersions: [.fragmentVersions[] | select(.status == "Approved") | {configuration, css, html, js, status}], icon, name, type} + (if $thumbnail != "" then {thumbnailURLReference: {fileBase64: $thumbnail}} else {} end)' <<< "$1"

	rm -f "$thumbnail"
}

# hotel_calls: the calls that open a hotel once the fragments are shared.
hotel_calls() {
	call PUT "$SITE_API/sites/{city}"
	call PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/{city}"
	call POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files"
	note "(twice: {city}-room.svg and {city}-ray.png, into the images folder)"
	call PUT "$SITE_API/sites/{city}/site-pages/hotel-home"
}

act3() {
	act "London opens" "A second hotel opens in London, where DevCon is today. With the fragments in the design library, a new hotel needs no fragments of its own: one step opens it."

	# UI: Applications Menu > Sites: Ray’s Hotel London appears. Then the London hotel page.
	step london "Open the London hotel"
	show "$SITES"
	show_after "$LONDON_PAGE"
	say "${B}The site, its connection to the library, its two images and its page:${R}"
	say ""
	hotel_calls
	say ""
	say "Its page uses the library’s Hotel Header with London’s city, address and color."
	wait_key "open London"
	say ""

	live && open_hotel "$LONDON_ERC" London
	refresh

	marker done london
	next
}

# thumbnail_file FRAGMENT_URL FILE: downloads the fragment's thumbnail into
# FILE. The first read after creating a fragment can come without the
# thumbnail URL, so it retries.
thumbnail_file() {
	local i url

	for i in 1 2 3 4 5; do
		url=$(api GET "$1?nestedFields=thumbnailURLReference" | jq -r '.thumbnailURLReference.url // empty | sub("&imageThumbnail=1"; "")')

		[ -n "$url" ] && break

		sleep 1
	done

	[ -n "$url" ] && curl -s -f -u "$LIFERAY_AUTH" -o "$2" "$url"
}

agent_tool_calls() {
	local log

	log=$(ls -t "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<< "$DIR/stage")"/*.jsonl 2> /dev/null | head -1)

	[ -z "$log" ] && return

	jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' "$log" |
		grep -v '^ToolSearch$' |
		sed -E 's/^mcp__liferay__/liferay › /'
}

act4() {
	act "The agent’s toolbox" "Ray wants an AI agent to help build the hotels’ fragments. Before it can, it needs a profile on Liferay’s MCP server: a briefing, and the only tools it may use. We create it through the API too."

	# UI: Applications Menu > MCP Server: the devcon profile appears.
	step profile "Create the agent’s MCP profile"
	show "$MCP_PROFILES"
	request PUT "$MCP_API/server-profiles/by-external-reference-code/$MCP_PROFILE_ERC" "$(mcp_profile_payload)" '{id, externalReferenceCode, profileStatus: .profileStatus.key}' "$(profile_body)"
	note "(the instructions brief the agent on Ray’s Hotels: mcp/instructions.md)"
	local profile_id tool
	profile_id=$(jq -r .id <<< "$LAST")
	next

	# UI: MCP Server > devcon > Tools: the seven tools.
	#   /group/control_panel/manage?p_p_id=com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet&p_p_lifecycle=0&p_p_state=maximized&_com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet_mvcRenderCommandName=%2Fmcp_server%2Fedit_profile&_com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet_profileERC=devcon&_com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet_tab=tools
	step profile-tools "Give it seven tools, from three headless APIs"
	show "$MCP_TOOLS_URL"
	say "${B}One PUT per tool, linked to the profile; the first one:${R}"
	show_path PUT "${MCP_API#"$LIFERAY_URL"}/server-profile-tools/by-external-reference-code/$MCP_PROFILE_ERC-${MCP_TOOLS[0]##*:}"
	mcp_tool_payload "$profile_id" "${MCP_TOOLS[0]}" | sed 's/^/ /' | colorize | HIGHLIGHT='"(toolSetName|toolName)"' highlight
	wait_key "add the seven tools"
	say ""
	say "${B}The seven tools, by tool set (a headless API):${R}"

	local tool_set=""

	live && for tool in "${MCP_TOOLS[@]}"; do
		if [ "${tool%%:*}" != "$tool_set" ]; then
			tool_set="${tool%%:*}"
			printf '  %s\n' "$tool_set"
		fi

		if api PUT "$MCP_API/server-profile-tools/by-external-reference-code/$MCP_PROFILE_ERC-${tool##*:}" "$(mcp_tool_payload "$profile_id" "$tool")" > /dev/null; then
			printf '    %s \033[32m✓\033[0m\n' "${tool##*:}"
		else
			printf '    %s \033[31m✗\033[0m\n' "${tool##*:}"
		fi
	done

	marker done profile-tools
	refresh
	next

	step profile-active "Activate the profile"
	show "$MCP_PROFILES"
	request PATCH "$MCP_API/server-profiles/by-external-reference-code/$MCP_PROFILE_ERC" '{"profileStatus": "active"}' '{externalReferenceCode, profileStatus: .profileStatus.key}'
	next

	step tools "List the tools the agent gets"
	request POST "$LIFERAY_URL/o/mcp/devcon" '{"id": 1, "jsonrpc": "2.0", "method": "tools/list"}' '[.result.tools[].name]'
	note "(Liferay generates these tools from the OpenAPI of each headless API)"
	next
}

act5() {
	act "An AI agent builds the next fragment" "Guests keep asking when breakfast is served. An AI agent creates a Breakfast Hours fragment in the design library, using only the tools of its MCP profile."

	step agent "Ask the agent"

	# Resuming past this step while Breakfast Hours is missing (the agent
	# failed): the step runs again.
	if [ -n "$SKIPPING" ] && [ -z "$REPLAYING" ] && ! library_fragment_exists "$BREAKFAST_FRAGMENT_ERC"; then
		SKIPPING=""
		RESUMING=""
		exec >&3
		header
	fi

	library_urls
	show "$LIBRARY_SET"
	say "${B}The prompt:${R}"
	fold -s -w "$(($(cols) - 4))" "$DIR/demo/02-prompt.txt" | sed 's/^/   /'
	say ""
	say "${B}The agent:${R} Claude Code, in an empty folder:"
	printf '   %sclaude%s "<the prompt>" \\\n' "$B" "$R"
	mcp_config "Basic …" | perl -0pe 's/\{\n\s*("Authorization": [^\n]*)\n\s*\}/{$1}/' | sed "1s/^/     --mcp-config '/; 2,\$s/^/       /; \$s/\$/' \\\\/" | colorize
	printf '     --strict-mcp-config \\\n'
	printf '     --model %s --effort %s \\\n' "$AGENT_MODEL" "$AGENT_EFFORT"
	printf '     --allowedTools %s \\\n' "$AGENT_ALLOWED_TOOLS"
	fold -s -w "$(( $(cols) - 26 ))" <<< "$AGENT_DISALLOWED_TOOLS" | sed 's/ *$//' | awk 'NR == 1 { printf "     --disallowedTools %s", $0; next } { printf " \\\n                       %s", $0 } END { print "" }'

	if [ -n "${AI_FALLBACK:-}" ]; then
		say ""
		note "AI_FALLBACK: creating the fragment from the cached agent run instead."

		live && cached_breakfast_hours
		refresh
	else
		wait_key "launch Claude Code"

		trap : INT

		if [ -n "$SKIPPING" ] && [ -n "$REPLAYING" ]; then
			cached_breakfast_hours
		else
			live && "$DIR/demo/02-ai-fragment.sh" > /dev/tty

			if live && ! library_fragment_exists "$BREAKFAST_FRAGMENT_ERC"; then
				header
				say ""
				note "The agent did not create Breakfast Hours (no network, or it was stopped)."
				wait_key "use the cached agent run instead"
				cached_breakfast_hours
				AI_FALLBACK=1
			fi
		fi
		refresh
	fi

	step agent-calls "Check the agent’s calls"

	if [ -n "${AI_FALLBACK:-}" ]; then
		cached_agent_run
	else
		say "${B}Every call the agent made went through Liferay’s MCP server:${R}"
		say ""
		agent_tool_calls | sed 's/^/   /'
	fi

	next

	trap - INT

	# UI: the library's Ray’s Hotel > Fragments: Breakfast Hours, still without a thumbnail.
	step read-breakfast "Read what the agent created"
	library_urls
	show_still "$LIBRARY_SET"
	request GET "$LIBRARY/fragments/$BREAKFAST_FRAGMENT_ERC" "" "$BREAKFAST_RESPONSE"
	note "(no thumbnail yet: the agent sent HTML, CSS and configuration only)"
	next

	local hours="$LAST" thumbnail_file

	thumbnail_file=$(mktemp --suffix=.png)

	if [ -n "$CHROME" ] && { ! live || render_thumbnail "$hours" "$thumbnail_file"; }; then

		# UI: the library's Ray’s Hotel > Fragments: Breakfast Hours with its thumbnail; then open it in the fragment editor.
		step breakfast-thumbnail "Give Breakfast Hours a thumbnail"
		library_urls
		show "$LIBRARY_SET"
		note "(a screenshot of the agent's HTML and CSS, taken with headless Chrome)"
		HIGHLIGHT='fileBase64' request PUT "$LIBRARY/fragments/$BREAKFAST_FRAGMENT_ERC" "$(jq -c --rawfile base64 <(base64 -w0 "$thumbnail_file") '{externalReferenceCode, fragmentVersions: [.fragmentVersions[] | select(.status == "Approved") | {configuration, css, html, js, status}], icon, name, thumbnailURLReference: {fileBase64: $base64}, type}' <<< "$hours")" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
		next
	fi

	rm -f "$thumbnail_file"

	if library_fragment_exists "$BREAKFAST_FRAGMENT_ERC"; then
		step breakfast-madrid "Add Breakfast Hours to Madrid’s page"
		show "$MADRID_PAGE"
		reveal_after
		HIGHLIGHT='rays-breakfast-hours' put_hotel_page "$MADRID_ERC" "library:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC" "library:$BREAKFAST_FRAGMENT_ERC"
		next

		# UI: the London hotel page, reloaded with Breakfast Hours.
		step breakfast-london "Add Breakfast Hours to London’s page"
		show "$LONDON_PAGE"
		reveal_after
		put_hotel_page "$LONDON_ERC" "library:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC" "library:$BREAKFAST_FRAGMENT_ERC"
		next
	fi
}

# open_hotel SITE_ERC CITY: a new hotel, the way London opened, on one line
# of the screen: its site, its connection to the design library, its images in
# the library and its page, with the library's fragments.
open_hotel() {
	local site="$1" city="$2"
	local fragments=("library:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC")

	printf "  %-15s" "$city"

	api PUT "$SITE_API/sites/$site" "{\"externalReferenceCode\": \"$site\", \"name\": \"Ray’s Hotel $city\"}" > /dev/null && tick site &&
		api PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/$site" '{"searchable": true}' > /dev/null && tick library &&
		api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/$(slug "$city")-room.svg" "$RESOURCE_FOLDER_ERC")" > /dev/null &&
		api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/$(slug "$city")-ray.png" "$RESOURCE_FOLDER_ERC")" > /dev/null && tick images ||
		{ printf ' \033[31m✗\033[0m\n'; return 1; }

	library_fragment_exists "$BREAKFAST_FRAGMENT_ERC" && fragments+=("library:$BREAKFAST_FRAGMENT_ERC")

	api PUT "$SITE_API/sites/$site/site-pages/hotel-home" "$(page_payload "$site" "${fragments[@]}")" > /dev/null && tick page && printf '\n' || printf ' \033[31m✗\033[0m\n'

	marker hotel "$site"
}

act6() {
	act "The next DevCon cities" "Ray’s Hotels follows DevCon: Madrid hosted it in 2025 and London hosts it now. Which city could host it next? Tenerife, Mykonos, Polignano a Mare, Sydney, Rio de Janeiro and Honolulu are candidates, and Ray opens a hotel in each, the way London opened."

	# UI: the hotel grid (demo/hotel-grid.py, http://localhost:8090): one tile per city, filled as each hotel opens.
	step hotels "Open the hotels of six possible future DevCon cities"
	show_still "$GRID_URL/"
	say "${B}For each city, the same calls as for London:${R}"
	say ""
	hotel_calls
	wait_key "open the hotels"
	say ""

	local city site name

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r site name _ _ <<< "$city"

		[ "$site" = "$MADRID_ERC" ] || [ "$site" = "$LONDON_ERC" ] && continue

		live && open_hotel "$site" "$name"
	done

	marker done hotels
	next

	# UI: the design library's connected sites: all eight hotels.
	step connected "List the hotels connected to the design library"
	library_urls
	show_still "$LIBRARY_VIEW"
	HIGHLIGHT='"totalCount"' request GET "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites?pageSize=20" "" '{totalCount, items: [.items[].name | sub("Ray’s Hotel "; "")]}'
	next
}

act7() {
	act "Early bird campaign" "The early bird season opens for the next DevCon. Marketing updates the Seasonal Offer once, in the design library, and the six new hotels get it with one propagation. Madrid and London, DevCon cities already, keep their DevCon guest rate."

	step early-bird-file "Upload the early bird image to the library"
	library_urls
	show "$LIBRARY_SET$RESOURCES&demoOpenFolder=$RESOURCE_FOLDER_ERC"
	reveal_after early-bird.svg
	request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/early-bird.svg" "$RESOURCE_FOLDER_ERC")" '{externalReferenceCode, resourceFolderExternalReferenceCode}'
	next

	# UI: the Madrid hotel page: still the DevCon guest rate.
	step early-bird-offer "Update the Seasonal Offer in the library"
	library_urls
	show "$LIBRARY_SET"
	show_after "$GRID_URL/"
	request PUT "$LIBRARY/fragments/$OFFER_FRAGMENT_ERC" "$(fragment_payload early-bird early-bird-configuration.json)" - "$FRAGMENT_BODY"
	compact || say ""
	say "Pages keep their copy of each fragment: the hotels still show the DevCon guest rate, until we propagate."
	show_sites
	next

	# UI: the library's Ray’s Hotel: Seasonal Offer > ⋮ > View Site Usages, select Madrid and London, Propagate.
	# Then both hotel pages.
	step propagate "Propagate to every hotel, from the UI"
	library_urls
	show_still "$LIBRARY_SET"
	say "Seasonal Offer > ⋮ > View Site Usages: select all the hotels, then Propagate."

	if browser_on; then
		wait_key "propagate in the browser"
		propagate_in_browser
	else
		wait_key "continue once you have propagated in the UI"
	fi

	hotels
	next
}

# propagate_in_browser: the propagation of act 7, clicked in the browser at a
# pace the audience can follow, then the hotel grid once the hotel pages have
# the winter offer (or after 60 seconds).
propagate_in_browser() {
	local title

	title=$(sed -nE 's/.*rays-offer__title"[^>]*>([^<]*)<.*/\1/p' "$DIR/payloads/seasonal-offer/early-bird/index.html")

	browser menu Seasonal Offer
	browser wait 2
	browser click View Site Usages
	browser wait 3
	browser check-all
	browser wait 2
	browser click Propagate
	browser wait 3
	browser goto "$GRID_URL/"

	for _ in $(seq 1 60); do
		[ "$(page_offer "$MADRID_ERC")" = "$title" ] && break

		sleep 1
	done
}

# the_end: Ray in front of a hotel (demo/the-end.ans, in octant block
# characters), or the words alone in a terminal too small for it.
the_end() {
	printf '\033[2J\033[3J\033[H'

	if [ "$(cols)" -lt 73 ] || [ "$(rows)" -lt 37 ]; then
		printf '\n %sThe end%s\n' "$B" "$R"

		return
	fi

	cat "$DIR/demo/the-end.ans"

	[ -n "${NO_PAUSE:-}" ] || read -rsn1 _ < /dev/tty 2> /dev/null
}

# demo_video: the demo video to play: DEMO_VIDEO, or else the newest
# devcon-demo*.mp4 in ~/tmp or the downloads folder that has its .acts file
# next to it.
demo_video() {
	local file

	if [ -n "${DEMO_VIDEO:-}" ]; then
		readlink -f "$DEMO_VIDEO"

		return
	fi

	ls -tL "$HOME"/tmp/devcon-demo*.mp4 "$HOME"/Downloads/devcon-demo*.mp4 "$(xdg-user-dir DOWNLOAD 2> /dev/null)"/devcon-demo*.mp4 2> /dev/null |
		while read -r file; do
			file=$(readlink -f "$file")

			[ -f "$file.acts" ] && { echo "$file"; break; }
		done
}

# play_video LAST_STEP: plays the demo video (demo_video), fullscreen, from
# the step after LAST_STEP: the first step not done. The start times are in
# VIDEO.acts, as the video recorder writes them: "ACT SECONDS" and
# "ACT.STEP SECONDS" lines. A step it does not list plays from its act.
play_video() {
	local act=1 acts second step=1 video

	video=$(demo_video)
	acts="$video.acts"

	if [ ! -f "$video" ] || [ ! -f "$acts" ]; then
		echo "No demo video: save devcon-demo-vNN.mp4 and devcon-demo-vNN.mp4.acts in ~/tmp or your downloads folder, or set DEMO_VIDEO to the video (with VIDEO.acts next to it)." >&2

		exit 1
	fi

	if [ -n "$1" ]; then
		act="${1%%.*}"
		step=$(( ${1#*.} + 1 ))

		if [ "$step" -gt "$(step_count "$act")" ] && [ "$act" -lt ${#ACT_NAMES[@]} ]; then
			act=$((act + 1))
			step=1
		fi
	fi

	second=$(awk -v step="$act.$step" '($1 "") == (step "") { print $2 }' "$acts")

	if [ -n "$second" ]; then
		printf 'Playing %s from step %s.%s (%s): space pauses, ← → jump 10 s, q quits.\n' "${video##*/}" "$act" "$step" "${ACT_NAMES[act - 1]}"
	else
		second=$(awk -v act="$act" '($1 "") == (act "") { print $2 }' "$acts")

		printf 'Playing %s from act %s (%s): space pauses, ← → jump 10 s, q quits.\n' "${video##*/}" "$act" "${ACT_NAMES[act - 1]}"
	fi

	env -u GDK_BACKEND ffplay -autoexit -fs -loglevel error -ss "${second:-0}" "$video" < /dev/null
}

# running_elsewhere: true when demo.sh runs in another terminal (its own
# subshells share its process group).
running_elsewhere() {
	local group pid

	group=$(ps -o pgid= -p $$ | tr -d ' ')

	for pid in $(pgrep -f '^(/usr/bin/)?bash (\S*/)?demo\.sh( |$)'); do
		[ "$(ps -o pgid= -p "$pid" | tr -d ' ')" = "$group" ] || return 0
	done

	return 1
}

# cached_agent_run: what the agent did in the run the cached Breakfast Hours
# comes from (payloads/breakfast-hours-run.json): its calls, and the start of
# its answer.
cached_agent_run() {
	local run="$DIR/payloads/breakfast-hours-run.json"

	say "${B}A rehearsal run of the agent: its calls to Liferay’s MCP server${R}"
	say ""
	jq -r '.calls[] | "   liferay › \(.)"' "$run"
	say ""
	say "${B}And the start of its answer:${R}"
	jq -r '.answer | gsub("[*`]"; "") | split("\n\n")[0:2] | join("\n\n")' "$run" | fold -s -w "$(( $(cols) - 6 ))" | head -9 | sed 's/^/   /'
	note "   …"
}

# cached_breakfast_hours: Breakfast Hours from the cached agent run, created,
# or updated when the agent got as far as creating it.
cached_breakfast_hours() {
	if library_fragment_exists "$BREAKFAST_FRAGMENT_ERC"; then
		api PUT "$LIBRARY/fragments/$BREAKFAST_FRAGMENT_ERC" "$DIR/payloads/breakfast-hours.json" > /dev/null
	else
		api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$DIR/payloads/breakfast-hours.json" > /dev/null
	fi
}

reset() {
	if running_elsewhere && [ -z "${FORCE:-}" ]; then
		echo "A demo is running in another terminal: stop it first (or FORCE=1 ./demo.sh reset)." >&2

		return 1
	fi

	rm -rf "$STATE_DIR"

	reset_portal

	echo "reset done: no hotel sites, no design library, no MCP profile"
}

# reset_portal: removes everything the demo creates from the portal, and
# keeps the record of the steps done.
reset_portal() {
	local city site

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r site _ _ _ <<< "$city"

		api DELETE "$SITE_API/sites/$site/site-pages/hotel-home" > /dev/null 2>&1
	done

	api DELETE "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" > /dev/null 2>&1

	local erc

	for erc in $(api GET "$MCP_API/server-profile-tools?pageSize=-1" 2> /dev/null | jq -r --arg prefix "$MCP_PROFILE_ERC-" '.items[] | select(.externalReferenceCode | startswith($prefix)) | .externalReferenceCode'); do
		api DELETE "$MCP_API/server-profile-tools/by-external-reference-code/$erc" > /dev/null 2>&1
	done

	api DELETE "$MCP_API/server-profiles/by-external-reference-code/$MCP_PROFILE_ERC" > /dev/null 2>&1

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r site _ _ _ <<< "$city"

		api DELETE "$SITE_API/sites/$site" > /dev/null 2>&1
	done
}

# help: the usage above, every act with its steps, and where resume goes on.
help() {
	local a last B="$B" R="$R"

	[ -t 1 ] || { B=""; R=""; }

	sed -n '3,/^$/{s/^# \{0,1\}//;p}' "$DIR/demo.sh" | sed '$d'

	printf '%sActs and steps%s\n' "$B" "$R"

	for ((a = 1; a <= ${#ACT_NAMES[@]}; a++)); do
		printf '\n %s%d. %s%s\n' "$B" "$a" "$(declare -f "act$a" | sed -nE 's/^\s*act "([^"]*)".*/\1/p')" "$R"

		declare -f "act$a" |
			sed -nE 's/^\s*step [^ ]+ "(.*)";?\s*$/\1/p' |
			sed -E 's/\$\([^)]*\)/…/g; s/\$[A-Za-z_]+/…/g' |
			awk -v act="$a" '{ printf "   %d.%-3d %s\n", act, NR, $0 }'
	done

	printf '\n With AI_FALLBACK=1 (or offline), 5.2 shows the calls of a rehearsal run.\n'

	last=$(sort -t. -k1,1n -k2,2n "$STATE_DIR/done" 2> /dev/null | tail -1)

	if [ -n "$last" ]; then
		printf '\n%sResume%s\n\n Steps done up to %s: ./demo.sh resume goes on from the first one not done after it.\n' "$B" "$R" "$last"
	else
		printf '\n%sResume%s\n\n Nothing done yet: ./demo.sh starts from the beginning.\n' "$B" "$R"
	fi
}

# stopped: on an exit before the end, how to go on from the act it stopped in.
stopped() {
	{ tput cnorm > /dev/tty; } 2> /dev/null
	[ -n "$SCREEN_LOG" ] && rm -f "$SCREEN_LOG"

	[ -n "$FINISHED" ] || [ "$ACT_NUMBER" = 0 ] && return

	printf '\n\n%sStopped in act %s. To go on from where it stopped: ./demo.sh resume%s\n' "$DIM" "$ACT_NUMBER" "$R"
}

# The run, as one function called from the file's last line: bash reads the
# whole of it before it starts, so editing demo.sh while it runs cannot break
# the run in progress.
main() {
	FINISHED=""

	local arg args=() fix="" video=""

	for arg in "$@"; do
		case "$arg" in
			offline) AI_FALLBACK=1 ;;
			fix) fix=1 ;;
			video) video=1 ;;
			*) args+=("$arg") ;;
		esac
	done

	set -- "${args[@]}"

	last=$(sort -t. -k1,1n -k2,2n "$STATE_DIR/done" 2> /dev/null | tail -1)

	if [ -n "$video" ]; then
		[ "${1:-}" = resume ] || last=""

		play_video "$last"

		return
	fi

	[ -t 1 ] && tput civis 2> /dev/null

	trap stopped EXIT

	case "${1:-}" in
		help | -h | --help | reset) ;;
		*) [ -t 1 ] && [ -z "${NO_PAUSE:-}" ] && log_screens ;;
	esac

	if [ "${1:-}" = resume ] && [ -z "$last" ]; then
		set --
	fi

	if [ "${1:-}" = resume ]; then
		RESUMING=1

		local first="${last%%.*}"

		if [ -n "$fix" ]; then
			if running_elsewhere; then
				echo "A demo is running in another terminal: stop it first." >&2

				exit 1
			fi

			printf '%sRebuilding the portal up to step %s, without showing it…%s\n' "$DIM" "$last" "$R"

			reset_portal

			REPLAYING="$last"
			first=1
		fi

		for ((a = first; a <= ${#ACT_NAMES[@]}; a++)); do
			"act$a"
		done

		step_done
		exec >&3
		the_end
		marker act done
	elif [ "${1:-}" = from ]; then
		for ((a = ${2#act}; a <= ${#ACT_NAMES[@]}; a++)); do
			"act$a"
		done

		the_end
		marker act done
	elif [ "${1:-}" = help ] || [ "${1:-}" = -h ] || [ "${1:-}" = --help ]; then
		help
	elif [ "${1:-}" = reset ]; then
		reset || exit 1
	elif [[ "${1:-}" =~ ^act[1-7]$ ]]; then
		"$1"
	elif [ $# -gt 0 ]; then
		printf 'Unknown command: %s\n\n' "$1"
		help

		exit 1
	else
		for ((a = 1; a <= ${#ACT_NAMES[@]}; a++)); do
			"act$a"
		done

		the_end
		marker act done
	fi

	FINISHED=1
}

main "$@"; exit
