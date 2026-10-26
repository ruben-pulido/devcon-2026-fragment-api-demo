#!/usr/bin/env bash
#
# One API, Thousands of Sites: step-by-step demo
#
#   ./demo.sh            run every act, pausing before each request
#   ./demo.sh act3       run a single act (act1 ... act6)
#   ./demo.sh reset      back to the starting point: Madrid with its store header
#
# NO_PAUSE=1 ./demo.sh   run without waiting for key presses
# AI_FALLBACK=1 ./demo.sh act4
#                        create the Store Hours fragment from the cached agent
#                        run instead of launching Claude Code
#
# Each screen shows the act's use case, the steps so far (the current one
# highlighted) and one API call. The "UI:" comments say what to show in the
# browser at each step.
#

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

source "$DIR/lib.sh"

LIBRARY="$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC"
MADRID="$FRAGMENT_API/sites/$MADRID_ERC"
LONDON="$FRAGMENT_API/sites/$LONDON_ERC"
ASSET_LIBRARY_API="$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries"

STORE_SET_ERC="rays-store"
HEADER_FRAGMENT_ERC="rays-store-header"

B=$'\033[1m'
DIM=$'\033[2m'
R=$'\033[0m'

ACT=""
ACT_TEXT=""
STEP=""
STEPS=()

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

# act TITLE TEXT
act() {
	ACT="$1"
	ACT_TEXT="$2"
	STEPS=()

	marker act "$ACT"
}

header() {
	local width i n

	width=$(cols)

	printf '\033[2J\033[3J\033[H'
	printf '\033[1;97;44m %-*s\033[0m\n' "$((width - 1))" "Ray’s Coffee · $ACT"
	fold -s -w "$((width - 2))" <<< "$ACT_TEXT" | sed "s/^/ ${B}/; s/\$/${R}/"
	compact || printf '\n'

	n=${#STEPS[@]}

	for ((i = 0; i < n; i++)); do
		if [ $i -eq $((n - 1)) ]; then
			printf ' \033[1;33m▶ %d. %s\033[0m\n' "$((i + 1))" "${STEPS[$i]}"
		else
			printf ' \033[32m✓\033[0m %s%d. %s%s\n' "$DIM" "$((i + 1))" "${STEPS[$i]}" "$R"
		fi
	done

	printf '%s%s%s\n' "$DIM" "$(printf '─%.0s' $(seq 1 "$width"))" "$R"
}

# step ID TEXT: a new step, on a clean screen.
step() {
	STEP="$1"
	STEPS+=("$2")

	marker step "$STEP"

	header
}

say() {
	fold -s -w "$(($(cols) - 2))" <<< "$*" | sed 's/^/ /'
}

note() {
	fold -s -w "$(($(cols) - 2))" <<< "$*" | sed "s/^/ ${DIM}/; s/\$/${R}/"
}

wait_key() {
	[ -n "${NO_PAUSE:-}" ] && return

	printf '\n%s[ press any key to %s ]%s' "$DIM" "$1" "$R"
	read -rsn1 _ < /dev/tty
	printf '\r\033[K\033[1A\033[K'
}

PATH_COLOR=$'\033[1;37m'
ERC_COLOR=$'\033[1;38;5;214m'

# Collections whose next path segment is an external reference code.
ERC_COLLECTIONS=" asset-libraries connected-sites design-libraries fragment-sets fragments mcp resource-folders resource-files site-pages sites "

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

		if [[ "$ERC_COLLECTIONS" == *" $previous "* ]]; then
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

HIGHLIGHT_BACKGROUND=$'\033[48;5;239m'

# highlight: the lines matching HIGHLIGHT (an extended regular expression)
# get a mark in the margin and a background, so the audience knows where to
# look.
highlight() {
	local line plain rest width

	width=$(($(cols) - 2))

	while IFS= read -r line; do
		plain=$(sed 's/\x1b\[[0-9;]*m//g' <<< "$line")

		if [ -n "${HIGHLIGHT:-}" ] && grep -qE -- "$HIGHLIGHT" <<< "$plain"; then
			rest="${line:1}"
			printf '\033[1;38;5;214m▌%s%s%*s%s\n' "${R}${HIGHLIGHT_BACKGROUND}" "${rest//$R/$R$HIGHLIGHT_BACKGROUND}" "$((width - ${#plain} + 1))" '' "$R"
		else
			printf '%s\n' "$line"
		fi
	done
}

LAST=""

# request METHOD URL [BODY] [RESPONSE_FILTER] [BODY_FILTER]
request() {
	local method="$1" url="$2" body="${3:-}" filter="${4:-.}" body_filter="${5:-.}"

	show_path "$method" "${url#$LIFERAY_URL}"

	local used

	used=$((${#STEPS[@]} + $(fold -s -w "$(($(cols) - 2))" <<< "$ACT_TEXT" | wc -l) + 12))

	compact && used=$((used - 4))

	if [ -n "$body" ] && [[ "$body_filter" == @* ]]; then
		jq -r "${body_filter#@}" <<< "$body" | sed 's/^/ /' | colorize | highlight
	elif [ -n "$body" ]; then
		show_json "$body" "$body_filter" "$(($(rows) - used - 4))" | colorize | highlight
	fi

	wait_key "send the request"

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

	compact || printf '\n'

	if [[ "$status" == 2* ]]; then
		printf ' \033[1;32m← %s OK\033[0m %s(%s ms)%s\n' "$status" "$DIM" "$elapsed" "$R"
	else
		printf ' \033[1;31m← %s\033[0m %s(%s ms)%s\n' "$status" "$DIM" "$elapsed" "$R"
	fi

	marker done "$STEP"

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

# put_store_page SITE_ERC SCOPE:FRAGMENT_ERC...
put_store_page() {
	local site="$1"

	shift

	request PUT "$SITE_API/sites/$site/site-pages/store-home" "$(page_payload "$@")" - "$PAGE_BODY"

	note "(each element also carries its fragment’s HTML, CSS and configuration)"
}

stores() {
	say ""
	say "${B}What the store pages show now:${R}"

	show_sites
}

act1() {
	act "Madrid opens" "The first Ray’s Coffee store opens in Madrid. Its Liferay site has been created; we create its first fragments and its home page through the headless APIs."

	# UI: Madrid > Design > Fragments > Ray’s Store: only the Store Header.
	#   /group/<madrid>/~/control_panel/manage/-/fragments/fragment_collections?_com_liferay_fragment_web_portlet_FragmentPortlet_fragmentCollectionExternalReferenceCode=rays-store
	marker step start
	header
	say "The starting point: the Madrid site, with its Store Header fragment."
	next

	# UI: Madrid > Design > Fragments: the Ray’s Campaigns set appears.
	step set "Create the Ray’s Campaigns fragment set"
	HIGHLIGHT='"name"' request PUT "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" '{"description": "Seasonal campaigns", "name": "Ray’s Campaigns"}' '{externalReferenceCode, name}'
	next

	# UI: Ray’s Campaigns > Resources tab (before the request): the images folder appears.
	#   ...fragment_collections?..._fragmentCollectionExternalReferenceCode=rays-campaigns&_com_liferay_fragment_web_portlet_FragmentPortlet_tabs1=resources
	step folder "Create the images resource folder"
	HIGHLIGHT='"name"' request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "{\"externalReferenceCode\": \"$RESOURCE_FOLDER_ERC\", \"name\": \"$RESOURCE_FOLDER_ERC\"}" '{externalReferenceCode, name}'
	next

	# UI: Resources > images: autumn-cup.svg appears.
	step file "Upload the autumn campaign image"
	HIGHLIGHT='resourceFolderExternalReferenceCode|fileBase64' request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/autumn-cup.svg" "$RESOURCE_FOLDER_ERC")" '{externalReferenceCode, name, resourceFolderExternalReferenceCode}'
	next

	# UI: Ray’s Campaigns > Fragments: Seasonal Promo appears, with its thumbnail.
	step promo "Create the Seasonal Promo fragment"
	HIGHLIGHT='"html"|"configuration"|fileBase64' request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(fragment_payload autumn configuration.json)" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
	next

	# UI: before the request, Madrid > Site Builder > Pages: no pages yet.
	#   /group/<madrid>/~/control_panel/manage?p_p_id=com_liferay_layout_admin_web_portlet_GroupPagesPortlet
	# After it, the same list with Store Home, then the Madrid store page.
	#   /web/<madrid>/store-home
	step page "Create Madrid’s store page"
	HIGHLIGHT='"(externalReferenceCode)": "rays-|"pageElements"' put_store_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "$MADRID_ERC:$PROMO_FRAGMENT_ERC"
	next
}

act2() {
	act "London opens" "A second store opens in London, with its own site and Store Header. We want to launch campaigns in all stores at the same time, so we create a design library and connect both sites to it."

	# UI: Applications Menu > Sites: Ray’s Coffee London appears.
	step london "Create the London site"
	HIGHLIGHT='"name"|friendlyUrlPath' request PUT "$SITE_API/sites/$LONDON_ERC" "{\"externalReferenceCode\": \"$LONDON_ERC\", \"name\": \"Ray’s Coffee London\"}" '{externalReferenceCode, name, friendlyUrlPath}'
	next

	api PUT "$LONDON/fragment-sets/$STORE_SET_ERC" '{"name": "Ray’s Store"}' > /dev/null
	api POST "$LONDON/fragment-sets/$STORE_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/london-ray.png")" > /dev/null

	# UI: London > Design > Fragments > Ray’s Store: the London Store Header, with its thumbnail.
	step header "Create London’s Store Header"
	HIGHLIGHT='fileBase64|"html"' request POST "$LONDON/fragment-sets/$STORE_SET_ERC/fragments" "$(header_payload London london-ray.png '#7cc4ff' '221 Baker Street, London')" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
	note "(its fragment set and header image were created the same way as Madrid’s)"
	next

	# UI: Applications Menu > Design Libraries: Ray’s Design Library appears.
	#   /group/control_panel/manage?p_p_id=com_liferay_design_library_web_internal_portlet_DesignLibraryAdminPortlet
	step library "Create the design library"
	HIGHLIGHT='"type"' request PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" "{\"externalReferenceCode\": \"$DESIGN_LIBRARY_ERC\", \"name\": \"Ray’s Design Library\", \"settings\": {}, \"type\": \"DesignLibrary\"}" '{externalReferenceCode, name, type}'
	next

	# UI: Design Libraries > Ray’s Design Library: its Connected Sites card, empty before the request, then with Madrid.
	step connect-madrid "Connect Madrid to the design library"
	HIGHLIGHT='"name"' request PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/$MADRID_ERC" '{"searchable": true}' '{externalReferenceCode, name}'
	next

	# UI: Ray’s Design Library: its Connected Sites card, with Madrid and London.
	step connect-london "Connect London to the design library"
	HIGHLIGHT='"name"' request PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/$LONDON_ERC" '{"searchable": true}' '{externalReferenceCode, name}'
	next
}

act3() {
	act "Share the campaigns" "The campaigns move from Madrid’s site to the design library, so both stores can use the same fragments. There is no move operation: we copy, repoint the pages and delete the originals."

	step read-set "Read the fragment set from Madrid"
	HIGHLIGHT='"name"|"description"' request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" "" '{externalReferenceCode, name, description}'
	local set="$LAST"
	next

	# UI: before the request, Design Libraries > Ray’s Design Library: no design resources yet.
	# After it, the library's fragment sets: Ray’s Campaigns.
	step put-set "Create it in the design library"
	HIGHLIGHT='"name"|"description"' request PUT "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC" "$(jq -c '{description, name}' <<< "$set")" '{externalReferenceCode, name}'
	next

	step read-folders "Read its resource folders"
	HIGHLIGHT='"name"' request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "" "$ITEMS"
	local folders="$LAST" folder
	next

	# UI: the library's Ray’s Campaigns > Resources tab: the images folder appears.
	while read -r folder; do
		step post-folder "Create the $(jq -r .name <<< "$folder") folder in the library"
		HIGHLIGHT='"name"' request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-folders" "$folder" '{externalReferenceCode, name}'
		next
	done < <(jq -c '.items[] | {externalReferenceCode, name}' <<< "$folders")

	local file files

	while read -r folder; do
		step read-files "Read the files in $folder"
		HIGHLIGHT='fileBase64' request GET "$FRAGMENT_API/sites/$MADRID_ERC/resource-folders/$folder/resource-files?nestedFields=fileURLReference.fileBase64" "" '[.items[] | {externalReferenceCode, fileURLReference: {fileBase64: .fileURLReference.fileBase64}}]'
		files="$LAST"
		next

		while read -r file; do
			step post-file "Copy $(jq -r .name <<< "$file") to the library"
			HIGHLIGHT='resourceFolderExternalReferenceCode|fileBase64' request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$file" '{externalReferenceCode, resourceFolderExternalReferenceCode}'
			next
		done < <(jq -c --arg folder "$folder" '.items[] | {externalReferenceCode, fileURLReference: {fileBase64: .fileURLReference.fileBase64}, name, resourceFolderExternalReferenceCode: $folder}' <<< "$files")
	done < <(jq -r '.items[].externalReferenceCode' <<< "$folders")

	step read-fragments "Read its fragments"
	HIGHLIGHT='"name"' request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "" "$ITEMS"
	local fragments="$LAST" fragment erc thumbnail
	next

	# UI: the library's Ray’s Campaigns > Fragments: Seasonal Promo, with its thumbnail.
	while read -r erc; do
		thumbnail=$(thumbnail_reference "$MADRID/fragments/$erc")
		fragment=$(jq -c --arg erc "$erc" --argjson thumbnail "$thumbnail" '.items[] | select(.externalReferenceCode == $erc) | {externalReferenceCode, fragmentVersions: [.fragmentVersions[] | select(.status == "Approved") | {configuration, css, html, js, status}], icon, name, type} + (if $thumbnail then {thumbnailURLReference: $thumbnail} else {} end)' <<< "$fragments")

		step post-fragment "Copy $(jq -r .name <<< "$fragment") to the library"
		HIGHLIGHT='"html"|"url"' request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$fragment" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
		next
	done < <(jq -r '.items[].externalReferenceCode' <<< "$fragments")

	# UI: the Madrid store page, unchanged.
	step madrid-page "Point Madrid’s page to the library’s promo"
	HIGHLIGHT='"scope"' put_store_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC"
	next

	# UI: Madrid and London, one under the other: http://localhost:8090/?cities=Madrid,London
	step london-page "Create London’s store page"
	HIGHLIGHT='"scope"' put_store_page "$LONDON_ERC" "$LONDON_ERC:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC"
	next

	# UI: Madrid > Design > Fragments: only Ray’s Store is left. Then Madrid and London (?cities=Madrid,London).
	step delete-set "Delete the fragment set from Madrid"
	request DELETE "$MADRID/fragment-sets/$FRAGMENT_SET_ERC"
	stores
	next
}

# thumbnail_reference FRAGMENT_URL: the fragment's thumbnail as a reference
# to copy it from. The first read after creating a fragment can come without
# the thumbnail URL, so it retries.
thumbnail_reference() {
	local i reference

	for i in 1 2 3 4 5; do
		reference=$(api GET "$1?nestedFields=thumbnailURLReference" | jq -c '.thumbnailURLReference | if .url then {url: (.url | sub("&imageThumbnail=1"; ""))} else null end')

		[ "$reference" != null ] && break

		sleep 1
	done

	printf '%s' "$reference"
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
	act "An AI agent builds the next fragment" "Customers keep asking about opening hours. An AI agent creates a Store Hours fragment in the design library. It can only use Liferay’s MCP server."

	# UI: MCP Server > devcon > Tools.
	#   /group/control_panel/manage?p_p_id=com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet&p_p_lifecycle=0&p_p_state=maximized&_com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet_mvcRenderCommandName=%2Fmcp_server%2Fedit_profile&_com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet_profileERC=devcon&_com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet_tab=tools
	step tools "List the tools the agent gets"
	HIGHLIGHT='Fragment|SitePage' request POST "$LIFERAY_URL/o/mcp/devcon" '{"id": 1, "jsonrpc": "2.0", "method": "tools/list"}' '[.result.tools[].name]'
	note "(Liferay generates these tools from the OpenAPI of each headless API)"
	next

	step agent "Ask the agent"
	say "${B}The prompt:${R}"
	fold -s -w "$(($(cols) - 4))" "$DIR/demo/02-prompt.txt" | sed 's/^/   /'
	say ""
	say "${B}The agent:${R} Claude Code, started with"
	say "  --mcp-config         Liferay’s MCP server only"
	say "  --disallowedTools    no shell, files or web"

	if [ -n "${AI_FALLBACK:-}" ]; then
		say ""
		note "AI_FALLBACK: creating the fragment from the cached agent run instead."

		api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$DIR/payloads/store-hours.json" > /dev/null
	else
		wait_key "launch Claude Code"

		"$DIR/demo/02-ai-fragment.sh"

		step agent-calls "Check the agent’s calls"
		say "${B}Every call the agent made went through Liferay’s MCP server:${R}"
		say ""
		agent_tool_calls | sed 's/^/   /'
	fi

	next

	# UI: the library's Ray’s Campaigns > Fragments: Store Hours, still without a thumbnail.
	step read-hours "Read what the agent created"
	HIGHLIGHT='"name"|colorPicker|: text' request GET "$LIBRARY/fragments/$HOURS_FRAGMENT_ERC" "" '{externalReferenceCode, name, fields: [.fragmentVersions[0].configuration.fieldSets[]?.fields[]? | "\(.name): \(.type)"]}'
	next

	local hours="$LAST" thumbnail_file

	thumbnail_file=$(mktemp --suffix=.png)

	if [ -n "$CHROME" ] && render_thumbnail "$hours" "$thumbnail_file"; then

		# UI: the library's Ray’s Campaigns > Fragments: Store Hours with its thumbnail; then open it in the fragment editor.
		step hours-thumbnail "Give Store Hours a thumbnail"
		note "(a screenshot of the agent's HTML and CSS, taken with headless Chrome)"
		HIGHLIGHT='fileBase64' request PUT "$LIBRARY/fragments/$HOURS_FRAGMENT_ERC" "$(jq -c --rawfile base64 <(base64 -w0 "$thumbnail_file") '{externalReferenceCode, fragmentVersions: [.fragmentVersions[] | select(.status == "Approved") | {configuration, css, html, js, status}], icon, name, thumbnailURLReference: {fileBase64: $base64}, type}' <<< "$hours")" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
		next
	fi

	rm -f "$thumbnail_file"

	if library_fragment_exists "$HOURS_FRAGMENT_ERC"; then
		step hours-madrid "Add Store Hours to Madrid’s page"
		HIGHLIGHT='rays-store-hours' put_store_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC" "library:$HOURS_FRAGMENT_ERC"
		next

		# UI: Madrid and London, one under the other (?cities=Madrid,London).
		step hours-london "Add Store Hours to London’s page"
		HIGHLIGHT='rays-store-hours' put_store_page "$LONDON_ERC" "$LONDON_ERC:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC" "library:$HOURS_FRAGMENT_ERC"
		next
	fi
}

# open_store YEAR SITE_ERC CITY ACCENT ADDRESS: a new store, the way London
# opened, on one line of the screen.
open_store() {
	local year="$1" site="$2" city="$3" accent="$4" address="$5" image="${3,,}-ray.png"
	local fragments=("$site:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC")

	printf '  %s %-10s' "$year" "$city"

	api PUT "$SITE_API/sites/$site" "{\"externalReferenceCode\": \"$site\", \"name\": \"Ray’s Coffee $city\"}" > /dev/null &&
		printf ' site \033[32m✓\033[0m' &&
		api PUT "$FRAGMENT_API/sites/$site/fragment-sets/$STORE_SET_ERC" '{"name": "Ray’s Store"}' > /dev/null &&
		api POST "$FRAGMENT_API/sites/$site/fragment-sets/$STORE_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/$image")" > /dev/null &&
		api POST "$FRAGMENT_API/sites/$site/fragment-sets/$STORE_SET_ERC/fragments" "$(header_payload "$city" "$image" "$accent" "$address")" > /dev/null &&
		printf '  header \033[32m✓\033[0m' &&
		api PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/$site" '{"searchable": true}' > /dev/null &&
		printf '  library \033[32m✓\033[0m' || { printf '  \033[31m✗\033[0m\n'; return 1; }

	library_fragment_exists "$HOURS_FRAGMENT_ERC" && fragments+=("library:$HOURS_FRAGMENT_ERC")

	api PUT "$SITE_API/sites/$site/site-pages/store-home" "$(page_payload "${fragments[@]}")" > /dev/null &&
		printf '  page \033[32m✓\033[0m\n' || printf '  \033[31m✗\033[0m\n'

	marker store "$site"
}

act5() {
	act "A store in every DevCon city" "Ray’s Coffee follows DevCon: Madrid hosted it in 2025 and London hosts it now. Ray’s opens a store in every city that has hosted DevCon since 2013, each with its own site and header, all sharing the design library."

	# UI: the store grid (demo/store-grid.py, http://localhost:8090): one tile per DevCon city, filled as each store opens.
	step stores "Open the stores of the other six DevCon cities"
	say "${B}For each city, the same calls as for London:${R}"
	say ""
	local e="$ERC_COLOR" p="$PATH_COLOR"

	printf ' %s\n' "  ${B}PUT${R}  ${p}…/headless-admin-site/v1.0/sites/${e}{city}${R}"
	printf ' %s\n' "  ${B}PUT${R}  ${p}…/sites/${e}{city}${p}/fragment-sets/${e}rays-store${R}"
	printf ' %s\n' "  ${B}POST${R} ${p}…/fragment-sets/${e}rays-store${p}/resource-files${R}"
	printf ' %s\n' "  ${B}POST${R} ${p}…/fragment-sets/${e}rays-store${p}/fragments${R}"
	printf ' %s\n' "  ${B}PUT${R}  ${p}…/asset-libraries/${e}rays-design-library${p}/${R}"
	printf ' %s\n' "         ${p}connected-sites/${e}{city}${R}"
	printf ' %s\n' "  ${B}PUT${R}  ${p}…/sites/${e}{city}${p}/site-pages/${e}store-home${R}"
	wait_key "open the stores"
	say ""

	local city year site name accent address

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r year site name accent address <<< "$city"

		[ "$site" = "$MADRID_ERC" ] || [ "$site" = "$LONDON_ERC" ] && continue

		open_store "$year" "$site" "$name" "$accent" "$address"
	done

	marker done stores
	next

	# UI: the design library's connected sites: all eight stores.
	step connected "List the stores connected to the design library"
	HIGHLIGHT='"totalCount"' request GET "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites?pageSize=20" "" '{totalCount, items: [.items[].name | sub("Ray’s Coffee "; "")]}'
	next
}

act6() {
	act "Winter campaign" "Winter arrives. Marketing updates the Seasonal Promo once, in the design library, and all eight stores get it with one propagation."

	step winter-file "Upload the winter image to the library"
	HIGHLIGHT='resourceFolderExternalReferenceCode|fileBase64' request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/winter-cup.svg" "$RESOURCE_FOLDER_ERC")" '{externalReferenceCode, resourceFolderExternalReferenceCode}'
	next

	# UI: the Madrid store page: still autumn.
	step winter-promo "Update the Seasonal Promo in the library"
	HIGHLIGHT='"html"|fileBase64' request PUT "$LIBRARY/fragments/$PROMO_FRAGMENT_ERC" "$(fragment_payload winter winter-configuration.json)" - "$FRAGMENT_BODY"
	compact || say ""
	say "Pages keep their copy of each fragment: the stores still show autumn."
	show_sites
	next

	# UI: the library's Ray’s Campaigns: Seasonal Promo > ⋮ > View Site Usages, select Madrid and London, Propagate.
	# Then both store pages.
	step propagate "Propagate to every store, from the UI"
	say "Seasonal Promo > ⋮ > View Site Usages: select all the stores, then Propagate."
	wait_key "continue once you have propagated in the UI"
	stores
	next
}

# the_end: Ray, Liferay's mascot (demo/ray.ans), beside the closing words
# (demo/the-end.ans), or the words alone in a terminal too small for them.
the_end() {
	local i lines=() text=()

	printf '\033[2J\033[3J\033[H'

	if [ "$(cols)" -lt 72 ] || [ "$(rows)" -lt 38 ]; then
		printf '\n %sThe end%s\n\n %sThank you!%s\n' "$B" "$R" "$B" "$R"

		return
	fi

	mapfile -t lines < "$DIR/demo/ray.ans"
	mapfile -t -O 6 text < "$DIR/demo/the-end.ans"

	text[23]="${B}Thank you!${R}"
	text[26]="Ray’s Coffee:"
	text[27]="8 stores, 1 design library,"
	text[28]="1 Fragment Headless API."

	for i in "${!lines[@]}"; do
		printf '%s' "${lines[$i]}"
		[ -n "${text[$i]:-}" ] && printf '\033[42G%s' "${text[$i]}"
		printf '\n'
	done
}

reset() {
	local city site

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r _ site _ _ _ <<< "$city"

		api DELETE "$SITE_API/sites/$site/site-pages/store-home" > /dev/null 2>&1
	done

	api DELETE "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" > /dev/null 2>&1

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r _ site _ _ _ <<< "$city"

		[ "$site" = "$MADRID_ERC" ] || api DELETE "$SITE_API/sites/$site" > /dev/null 2>&1
	done
	api DELETE "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" > /dev/null 2>&1

	echo "reset done: Madrid has $(api GET "$MADRID/fragment-sets" | jq -r .totalCount) fragment set(s), no store page; no other stores, no design library"
}

if [ -t 1 ]; then
	tput civis 2> /dev/null
	trap 'tput cnorm 2> /dev/null' EXIT
fi

if [ $# -gt 0 ]; then
	"$1"
else
	for a in act1 act2 act3 act4 act5 act6; do
		"$a"
	done

	the_end
	marker act done
fi
