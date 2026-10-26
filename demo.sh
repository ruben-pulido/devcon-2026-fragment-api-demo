#!/usr/bin/env bash
#
# One API, Thousands of Sites: step-by-step demo
#
#   ./demo.sh            run every act, pausing before each request
#   ./demo.sh act3       run a single act (act1 ... act7)
#   ./demo.sh resume     go on from the first step not done yet, after the
#                        demo stopped
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

HOTEL_SET_ERC="rays-hotel"
HEADER_FRAGMENT_ERC="rays-hotel-header"

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
SKIPPING=""
CURRENT=""

exec 3>&1

# The acts' short names on the progress bar, the same as the browser's
# bookmark folders.
ACT_NAMES=(Madrid London "Design Library" MCP Agent Cities Winter)

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

# act TITLE TEXT, called from actN.
act() {
	step_done
	ACT="$1"
	ACT_NUMBER="${FUNCNAME[1]#act}"
	ACT_TEXT="$2"
	STEPS=()

	if [ -n "$RESUMING" ]; then
		skip_if_done "$ACT_NUMBER.1"
	else
		forget_from "$ACT_NUMBER"
	fi

	marker act "$ACT"
}

# step_count N: the number of steps of act N.
step_count() {
	declare -f "act$1" | grep -E '^\s*step ' | { [ -n "${AI_FALLBACK:-}" ] && grep -v 'step agent-calls' || cat; } | wc -l
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

	for ((i = 0; i < n; i++)); do
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
	if grep -qxF "$1" "$STATE_DIR/done" 2> /dev/null; then
		SKIPPING=1
		exec > /dev/null
	else
		SKIPPING=""
		RESUMING=""
		exec >&3
	fi
}

# forget_from ACT: a new run of an act forgets it and the acts after it.
forget_from() {
	mkdir -p "$STATE_DIR"
	touch "$STATE_DIR/done"
	awk -F. -v act="$1" '$1 < act' "$STATE_DIR/done" > "$STATE_DIR/done.new"
	mv "$STATE_DIR/done.new" "$STATE_DIR/done"
}

# live: true unless the step is being skipped.
live() {
	[ -z "$SKIPPING" ]
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

	used=$((${#STEPS[@]} + $(fold -s -w "$(($(cols) - 2))" <<< "$ACT_TEXT" | wc -l) + 14))

	compact && used=$((used - 4))

	if [ -n "$body" ] && [[ "$body_filter" == @* ]]; then
		jq -r "${body_filter#@}" <<< "$body" | sed 's/^/ /' | colorize | highlight
	elif [ -n "$body" ]; then
		show_json "$body" "$body_filter" "$(($(rows) - used - 4))" | colorize | highlight
	fi

	wait_key "send the request"

	if [ -n "$SKIPPING" ]; then
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

	shown=$(show_json "$LAST" "$filter" 14)

	if [ -n "$shown" ]; then
		colorize <<< "$shown" | highlight
	else
		printf '%s\n' "$LAST" | head -5
	fi
}

next() {
	wait_key "continue"
}

# The browser follows the demo through demo/browser-driver.mjs, when the demo
# browser runs with its remote control (demo/browser.sh) and DEMO_BROWSER is
# not 0. show URL shows a screen when a step starts and reloads it once the
# step's request has changed something; show_still shows one that needs no
# reload (the hotel grid reloads its own tiles); show_after shows a second
# screen a couple of seconds after that reload, such as the page just created
# after the list of pages. The design library's screens need its id, which
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

show() {
	browser goto "$1"
	BROWSER_RELOAD=1
}

show_still() {
	browser goto "$1"
	BROWSER_RELOAD=""
}

show_after() {
	BROWSER_AFTER="$1"
}

refresh() {
	[ -n "$BROWSER_RELOAD" ] && browser reload

	if [ -n "$BROWSER_AFTER" ]; then
		browser wait 2
		browser goto "$BROWSER_AFTER"
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
# wrapped to the screen, in yellow, as raw lines for request.
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
($lines | to_entries[] | "    \u001b[1;33m" + (if .key == 0 then "\"" else " " end) + .value + "\u001b[0m"),
"     \u001b[1;33m…\"\u001b[0m,",
"  \"profileStatus\": \"\(.profileStatus)\"",
"}"
EOF
}

FRAGMENT_BODY='{externalReferenceCode, name, fragmentVersions: [.fragmentVersions[] | {html, css} + ([.configuration.fieldSets[]?.fields[]?.name] | if length > 0 then {configuration: join(", ")} else {} end)], thumbnailURLReference}'
FRAGMENT_RESPONSE='{externalReferenceCode, name}'
# The page as the Pages API receives it, with the fragment content each page
# element also carries left out, so it fits on one screen.
PAGE_BODY='@
	def element($last):
		.pageElementDefinition.fragmentInstance.fragmentReference as $reference |
		[
			"    {\"pageElementDefinition\": {\"fragmentInstance\": {",
			"      \"fragmentReference\": {"
		] +
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

	request PUT "$SITE_API/sites/$site/site-pages/hotel-home" "$(page_payload "$@")" - "$PAGE_BODY"

	note "(each element also carries its fragment’s HTML, CSS and configuration)"
}

hotels() {
	say ""
	say "${B}What the hotel pages show now:${R}"

	show_sites
}

act1() {
	act "Madrid opens" "Ray’s Hotels opens its first hotel, in Madrid. We build it all through the headless APIs: its site, its header, its first campaign and its home page."

	# UI: Applications Menu > Sites: Ray’s Hotel Madrid appears.
	step site "Create the Madrid site"
	show "$SITES"
	request PUT "$SITE_API/sites/$MADRID_ERC" "{\"externalReferenceCode\": \"$MADRID_ERC\", \"name\": \"Ray’s Hotel Madrid\"}" '{externalReferenceCode, name, friendlyUrlPath}'
	next

	# UI: Madrid > Design > Fragments: the Ray’s Hotel set appears.
	step hotel-set "Create the Ray’s Hotel fragment set"
	show "$MADRID_ADMIN$FRAGMENTS=$HOTEL_SET_ERC"
	request PUT "$MADRID/fragment-sets/$HOTEL_SET_ERC" '{"name": "Ray’s Hotel"}' '{externalReferenceCode, name}'
	next

	# UI: Ray’s Hotel > Resources tab: madrid-room.svg appears.
	step view-image "Upload the view from a Madrid room"
	show "$MADRID_ADMIN$FRAGMENTS=$HOTEL_SET_ERC$RESOURCES"
	request POST "$MADRID/fragment-sets/$HOTEL_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/madrid-room.svg")" '{externalReferenceCode, name}'
	next

	# UI: Ray’s Hotel > Resources tab: madrid-ray.png appears too.
	step ray-image "Upload Ray, in Madrid’s colors"
	show "$MADRID_ADMIN$FRAGMENTS=$HOTEL_SET_ERC$RESOURCES"
	request POST "$MADRID/fragment-sets/$HOTEL_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/madrid-ray.png")" '{externalReferenceCode, name}'
	next

	# UI: Ray’s Hotel > Fragments: the Madrid Hotel Header, with its thumbnail.
	#   /group/<madrid>/~/control_panel/manage/-/fragments/fragment_collections?_com_liferay_fragment_web_portlet_FragmentPortlet_fragmentCollectionExternalReferenceCode=rays-hotel
	step header "Create Madrid’s Hotel Header"
	show "$MADRID_ADMIN$FRAGMENTS=$HOTEL_SET_ERC"
	request POST "$MADRID/fragment-sets/$HOTEL_SET_ERC/fragments" "$(header_payload Madrid madrid-room.svg '#f2b84b' 'Calle de Alcalá 42, Madrid')" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
	next

	# UI: Madrid > Design > Fragments: the Ray’s Campaigns set appears.
	step set "Create the Ray’s Campaigns fragment set"
	show "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request PUT "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" '{"description": "Seasonal campaigns", "name": "Ray’s Campaigns"}' '{externalReferenceCode, name}'
	next

	# UI: Ray’s Campaigns > Resources tab (before the request): the images folder appears.
	#   ...fragment_collections?..._fragmentCollectionExternalReferenceCode=rays-campaigns&_com_liferay_fragment_web_portlet_FragmentPortlet_tabs1=resources
	step folder "Create the images resource folder"
	show "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES"
	request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "{\"externalReferenceCode\": \"$RESOURCE_FOLDER_ERC\", \"name\": \"$RESOURCE_FOLDER_ERC\"}" '{externalReferenceCode, name}'
	next

	# UI: Resources > images: autumn-getaway.svg appears.
	step file "Upload the autumn campaign image"
	show "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES&demoOpenFolder=$RESOURCE_FOLDER_ERC"
	HIGHLIGHT='resourceFolderExternalReferenceCode' request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/autumn-getaway.svg" "$RESOURCE_FOLDER_ERC")" '{externalReferenceCode, name, resourceFolderExternalReferenceCode}'
	next

	# UI: Ray’s Campaigns > Fragments: Seasonal Offer appears, with its thumbnail.
	step offer "Create the Seasonal Offer fragment"
	show "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(fragment_payload autumn configuration.json)" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
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

# site_calls: the calls that open a hotel's site, as for Madrid.
site_calls() {
	local e="$ERC_COLOR" p="$PATH_COLOR"

	printf ' %s\n' "  ${B}PUT${R}  ${p}…/headless-admin-site/v1.0/sites/${e}{city}${R}"
	printf ' %s\n' "  ${B}PUT${R}  ${p}…/sites/${e}{city}${p}/fragment-sets/${e}rays-hotel${R}"
	printf ' %s\n' "  ${B}POST${R} ${p}…/fragment-sets/${e}rays-hotel${p}/resource-files${R} ×2"
	printf ' %s\n' "  ${B}POST${R} ${p}…/fragment-sets/${e}rays-hotel${p}/fragments${R}"
}

act2() {
	act "London opens" "A second hotel opens in London. Campaigns must launch in every hotel at the same time, so we create a design library and connect both sites to it."

	local year site name accent address

	IFS='|' read -r year site name accent address <<< "$(printf '%s\n' "${DEVCON_CITIES[@]}" | grep -F "|$LONDON_ERC|")"

	# UI: Applications Menu > Sites: Ray’s Hotel London appears. Then London > Design > Fragments > Ray’s Hotel: the London Hotel Header.
	step london "Open the London site, the same way as Madrid"
	show "$SITES"
	show_after "$LONDON_ADMIN$FRAGMENTS=$HOTEL_SET_ERC"
	say "${B}The same calls as for Madrid, with London’s header:${R}"
	say ""
	site_calls
	wait_key "open the London site"
	say ""

	live && open_site "$year" "$site" "$name" "$accent" "$address" && printf '\n'
	refresh

	marker done london
	next

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

	# UI: Ray’s Design Library: its Connected Sites card, with Madrid and London.
	step connect-london "Connect London to the design library"
	library_urls
	show "$LIBRARY_VIEW"
	request PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/$LONDON_ERC" '{"searchable": true}' '{externalReferenceCode, name}'
	next
}

act3() {
	act "Share the campaigns" "The campaigns move from Madrid’s site to the design library, so both hotels can use the same fragments. There is no move operation: we copy, repoint the pages and delete the originals."

	step read-set "Read the fragment set from Madrid"
	show_still "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" "" '{externalReferenceCode, name, description}'
	local set="$LAST"
	next

	# UI: before the request, Design Libraries > Ray’s Design Library: no design resources yet.
	# After it, the library's fragment sets: Ray’s Campaigns.
	step put-set "Create it in the design library"
	library_urls
	show "$LIBRARY_VIEW"
	show_after "$LIBRARY_SET"
	request PUT "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC" "$(jq -c '{description, name}' <<< "$set")" '{externalReferenceCode, name}'
	next

	step read-folders "Read its resource folders"
	show_still "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES"
	request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "" "$ITEMS"
	local folders="$LAST" folder
	next

	# UI: the library's Ray’s Campaigns > Resources tab: the images folder appears.
	while read -r folder; do
		step post-folder "Create the $(jq -r .name <<< "$folder") folder in the library"
		library_urls
		show "$LIBRARY_SET$RESOURCES"
		request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "$folder" '{externalReferenceCode, name}'
		next
	done < <(jq -c '.items[] | {externalReferenceCode, name}' <<< "$folders")

	local file files

	while read -r folder; do
		step read-files "Read the files in $folder"
		show_still "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC$RESOURCES&demoOpenFolder=$folder"
		request GET "$FRAGMENT_API/sites/$MADRID_ERC/resource-folders/$folder/resource-files?nestedFields=fileURLReference.fileBase64" "" '[.items[] | {externalReferenceCode, fileURLReference: {fileBase64: .fileURLReference.fileBase64}}]'
		files="$LAST"
		next

		while read -r file; do
			step post-file "Copy $(jq -r .name <<< "$file") to the library"
			library_urls
			show "$LIBRARY_SET$RESOURCES&demoOpenFolder=$folder"
			request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$file" '{externalReferenceCode, resourceFolderExternalReferenceCode}'
			next
		done < <(jq -c --arg folder "$folder" '.items[] | {externalReferenceCode, fileURLReference: {fileBase64: .fileURLReference.fileBase64}, name, resourceFolderExternalReferenceCode: $folder}' <<< "$files")
	done < <(jq -r '.items[].externalReferenceCode' <<< "$folders")

	step read-fragments "Read its fragments"
	show_still "$MADRID_ADMIN$FRAGMENTS=$FRAGMENT_SET_ERC"
	request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "" "$ITEMS"
	local fragments="$LAST" fragment erc thumbnail

	thumbnail=$(mktemp)
	next

	# UI: the library's Ray’s Campaigns > Fragments: Seasonal Offer, with its thumbnail.
	while read -r erc; do
		thumbnail_file "$MADRID/fragments/$erc" "$thumbnail" || : > "$thumbnail"
		fragment=$(jq -c --arg erc "$erc" --rawfile thumbnail <(base64 -w0 "$thumbnail") '.items[] | select(.externalReferenceCode == $erc) | {externalReferenceCode, fragmentVersions: [.fragmentVersions[] | select(.status == "Approved") | {configuration, css, html, js, status}], icon, name, type} + (if $thumbnail != "" then {thumbnailURLReference: {fileBase64: $thumbnail}} else {} end)' <<< "$fragments")

		step post-fragment "Copy $(jq -r .name <<< "$fragment") to the library"
		library_urls
		show "$LIBRARY_SET"
		request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$fragment" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
		next
	done < <(jq -r '.items[].externalReferenceCode' <<< "$fragments")

	rm -f "$thumbnail"

	# UI: the Madrid hotel page, unchanged.
	step madrid-page "Point Madrid’s page to the library’s offer"
	show "$MADRID_PAGE"
	HIGHLIGHT='rays-design-library' put_hotel_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC"
	next

	# UI: Madrid and London, one under the other: http://localhost:8090/?cities=Madrid,London
	step london-page "Create London’s hotel page"
	show_still "$GRID_URL/?cities=Madrid,London"
	put_hotel_page "$LONDON_ERC" "$LONDON_ERC:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC"
	next

	# UI: Madrid > Design > Fragments: only Ray’s Hotel is left. Then Madrid and London (?cities=Madrid,London).
	step delete-set "Delete the fragment set from Madrid"
	show "$MADRID_ADMIN$FRAGMENTS=$HOTEL_SET_ERC"
	show_after "$GRID_URL/?cities=Madrid,London"
	request DELETE "$MADRID/fragment-sets/$FRAGMENT_SET_ERC"
	hotels
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
	act "The agent’s toolbox" "Ray’s wants an AI agent to help build the hotels’ fragments. Before it can, it needs a profile on Liferay’s MCP server: a briefing, and the only tools it may use. We create it through the API too."

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
	printf ' %s\n' "${B}For each tool, its tool set (a headless API) and its name:${R}" ""
	printf ' %s\n' "  ${B}PUT${R}  ${PATH_COLOR}…/o/mcp/server-profile-tools/${R}"
	printf ' %s\n' "         ${PATH_COLOR}by-external-reference-code/${ERC_COLOR}devcon-{tool}${R}"
	wait_key "add the tools"
	say ""

	live && for tool in "${MCP_TOOLS[@]}"; do
		if api PUT "$MCP_API/server-profile-tools/by-external-reference-code/$MCP_PROFILE_ERC-${tool##*:}" "$(mcp_tool_payload "$profile_id" "$tool")" > /dev/null; then
			printf '  %-27s %s \033[32m✓\033[0m\n' "${tool%%:*}" "${tool##*:}"
		else
			printf '  %-27s %s \033[31m✗\033[0m\n' "${tool%%:*}" "${tool##*:}"
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
	library_urls
	show "$LIBRARY_SET"
	say "${B}The prompt:${R}"
	fold -s -w "$(($(cols) - 4))" "$DIR/demo/02-prompt.txt" | sed 's/^/   /'
	say ""
	say "${B}The agent:${R} Claude Code, in an empty folder:"
	printf '   %sclaude%s "<the prompt>" \\\n' "$B" "$R"
	printf '     --mcp-config .mcp.json --strict-mcp-config \\\n'
	printf '     --allowedTools %s \\\n' "$AGENT_ALLOWED_TOOLS"
	fold -s -w "$(( $(cols) - 26 ))" <<< "$AGENT_DISALLOWED_TOOLS" | sed 's/ *$//' | awk 'NR == 1 { printf "     --disallowedTools %s", $0; next } { printf " \\\n                       %s", $0 } END { print "" }'
	note "   (.mcp.json: only Liferay’s MCP server, ${MCP_API#$LIFERAY_URL}/$MCP_PROFILE_ERC)"

	if [ -n "${AI_FALLBACK:-}" ]; then
		say ""
		note "AI_FALLBACK: creating the fragment from the cached agent run instead."

		live && api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$DIR/payloads/breakfast-hours.json" > /dev/null
		refresh
	else
		wait_key "launch Claude Code"

		trap : INT

		live && "$DIR/demo/02-ai-fragment.sh" > /dev/tty
		refresh

		step agent-calls "Check the agent’s calls"
		say "${B}Every call the agent made went through Liferay’s MCP server:${R}"
		say ""
		agent_tool_calls | sed 's/^/   /'
	fi

	next

	trap - INT

	# UI: the library's Ray’s Campaigns > Fragments: Breakfast Hours, still without a thumbnail.
	step read-breakfast "Read what the agent created"
	library_urls
	show_still "$LIBRARY_SET"
	HIGHLIGHT='colorPicker|: text' request GET "$LIBRARY/fragments/$BREAKFAST_FRAGMENT_ERC" "" '{externalReferenceCode, name, fields: [.fragmentVersions[0].configuration.fieldSets[]?.fields[]? | "\(.name): \(.type)"]}'
	next

	local hours="$LAST" thumbnail_file

	thumbnail_file=$(mktemp --suffix=.png)

	if [ -n "$CHROME" ] && { ! live || render_thumbnail "$hours" "$thumbnail_file"; }; then

		# UI: the library's Ray’s Campaigns > Fragments: Breakfast Hours with its thumbnail; then open it in the fragment editor.
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
		show_still "$GRID_URL/?cities=Madrid,London"
		HIGHLIGHT='rays-breakfast-hours' put_hotel_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC" "library:$BREAKFAST_FRAGMENT_ERC"
		next

		# UI: Madrid and London, one under the other (?cities=Madrid,London).
		step breakfast-london "Add Breakfast Hours to London’s page"
		put_hotel_page "$LONDON_ERC" "$LONDON_ERC:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC" "library:$BREAKFAST_FRAGMENT_ERC"
		next
	fi
}

# open_hotel YEAR SITE_ERC CITY ACCENT ADDRESS: a new hotel, the way London
# opened, on one line of the screen.
# open_site YEAR SITE_ERC CITY ACCENT ADDRESS: a hotel's site, fragment set,
# header image and Hotel Header, on one line of ticks.
open_site() {
	local year="$1" site="$2" city="$3" accent="$4" address="$5" image="${3,,}-room.svg"

	printf '  %s %-10s' "$year" "$city"

	api PUT "$SITE_API/sites/$site" "{\"externalReferenceCode\": \"$site\", \"name\": \"Ray’s Hotel $city\"}" > /dev/null &&
		printf ' site \033[32m✓\033[0m' &&
		api PUT "$FRAGMENT_API/sites/$site/fragment-sets/$HOTEL_SET_ERC" '{"name": "Ray’s Hotel"}' > /dev/null &&
		api POST "$FRAGMENT_API/sites/$site/fragment-sets/$HOTEL_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/$image")" > /dev/null &&
		api POST "$FRAGMENT_API/sites/$site/fragment-sets/$HOTEL_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/${city,,}-ray.png")" > /dev/null &&
		api POST "$FRAGMENT_API/sites/$site/fragment-sets/$HOTEL_SET_ERC/fragments" "$(header_payload "$city" "$image" "$accent" "$address")" > /dev/null &&
		printf '  header \033[32m✓\033[0m' || { printf '  \033[31m✗\033[0m\n'; return 1; }
}

open_hotel() {
	local year="$1" site="$2" city="$3" accent="$4" address="$5"
	local fragments=("$site:$HEADER_FRAGMENT_ERC" "library:$OFFER_FRAGMENT_ERC")

	open_site "$@" || return 1

	api PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/$site" '{"searchable": true}' > /dev/null &&
		printf '  library \033[32m✓\033[0m' || { printf '  \033[31m✗\033[0m\n'; return 1; }

	library_fragment_exists "$BREAKFAST_FRAGMENT_ERC" && fragments+=("library:$BREAKFAST_FRAGMENT_ERC")

	api PUT "$SITE_API/sites/$site/site-pages/hotel-home" "$(page_payload "${fragments[@]}")" > /dev/null &&
		printf '  page \033[32m✓\033[0m\n' || printf '  \033[31m✗\033[0m\n'

	marker hotel "$site"
}

act6() {
	act "A hotel in every DevCon city" "Ray’s Hotels follows DevCon: Madrid hosted it in 2025 and London hosts it now. Ray’s opens a hotel in every city that has hosted DevCon since 2013, each with its own site and header, all sharing the design library."

	# UI: the hotel grid (demo/hotel-grid.py, http://localhost:8090): one tile per DevCon city, filled as each hotel opens.
	step hotels "Open the hotels of the other six DevCon cities"
	show_still "$GRID_URL/"
	say "${B}For each city, the same calls as for London:${R}"
	say ""
	local e="$ERC_COLOR" p="$PATH_COLOR"

	site_calls
	printf ' %s\n' "  ${B}PUT${R}  ${p}…/asset-libraries/${e}rays-design-library${p}/${R}"
	printf ' %s\n' "         ${p}connected-sites/${e}{city}${R}"
	printf ' %s\n' "  ${B}PUT${R}  ${p}…/sites/${e}{city}${p}/site-pages/${e}hotel-home${R}"
	wait_key "open the hotels"
	say ""

	local city year site name accent address

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r year site name accent address <<< "$city"

		[ "$site" = "$MADRID_ERC" ] || [ "$site" = "$LONDON_ERC" ] && continue

		live && open_hotel "$year" "$site" "$name" "$accent" "$address"
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
	act "Winter campaign" "Winter arrives. Marketing updates the Seasonal Offer once, in the design library, and all eight hotels get it with one propagation."

	step winter-file "Upload the winter image to the library"
	library_urls
	show "$LIBRARY_SET$RESOURCES&demoOpenFolder=$RESOURCE_FOLDER_ERC"
	request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/winter-getaway.svg" "$RESOURCE_FOLDER_ERC")" '{externalReferenceCode, resourceFolderExternalReferenceCode}'
	next

	# UI: the Madrid hotel page: still autumn.
	step winter-offer "Update the Seasonal Offer in the library"
	show_still "$GRID_URL/"
	request PUT "$LIBRARY/fragments/$OFFER_FRAGMENT_ERC" "$(fragment_payload winter winter-configuration.json)" - "$FRAGMENT_BODY"
	compact || say ""
	say "Pages keep their copy of each fragment: the hotels still show autumn."
	show_sites
	next

	# UI: the library's Ray’s Campaigns: Seasonal Offer > ⋮ > View Site Usages, select Madrid and London, Propagate.
	# Then both hotel pages.
	step propagate "Propagate to every hotel, from the UI"
	library_urls
	show_still "$LIBRARY_SET"
	say "Seasonal Offer > ⋮ > View Site Usages: select all the hotels, then Propagate."
	wait_key "continue once you have propagated in the UI"
	show_still "$GRID_URL/"
	hotels
	next
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

reset() {
	local city site

	rm -rf "$STATE_DIR"

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r _ site _ _ _ <<< "$city"

		api DELETE "$SITE_API/sites/$site/site-pages/hotel-home" > /dev/null 2>&1
	done

	api DELETE "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" > /dev/null 2>&1

	local erc

	for erc in $(api GET "$MCP_API/server-profile-tools?pageSize=-1" 2> /dev/null | jq -r --arg prefix "$MCP_PROFILE_ERC-" '.items[] | select(.externalReferenceCode | startswith($prefix)) | .externalReferenceCode'); do
		api DELETE "$MCP_API/server-profile-tools/by-external-reference-code/$erc" > /dev/null 2>&1
	done

	api DELETE "$MCP_API/server-profiles/by-external-reference-code/$MCP_PROFILE_ERC" > /dev/null 2>&1

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r _ site _ _ _ <<< "$city"

		api DELETE "$SITE_API/sites/$site" > /dev/null 2>&1
	done

	echo "reset done: no hotel sites, no design library, no MCP profile"
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

	printf '\n With AI_FALLBACK=1, act 5 skips "Check the agent’s calls".\n'

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

	[ -t 1 ] && tput civis 2> /dev/null

	trap stopped EXIT

	case "${1:-}" in
		help | -h | --help | reset) ;;
		*) [ -t 1 ] && [ -z "${NO_PAUSE:-}" ] && log_screens ;;
	esac

	if [ "${1:-}" = resume ]; then
		last=$(sort -t. -k1,1n -k2,2n "$STATE_DIR/done" 2> /dev/null | tail -1)

		if [ -z "$last" ]; then
			echo "Nothing to resume: run ./demo.sh"

			exit 1
		fi

		RESUMING=1

		for ((a = ${last%%.*}; a <= ${#ACT_NAMES[@]}; a++)); do
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
	elif [[ "${1:-}" =~ ^(act[1-7]|reset)$ ]]; then
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
