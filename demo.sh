#!/usr/bin/env bash
#
# One API, Thousands of Sites: step-by-step demo
#
#   ./demo.sh            run every step, pausing before each request
#   ./demo.sh step3      run a single step (step0 ... step7)
#   ./demo.sh reset      back to the starting point (library and sites, nothing else)
#
# NO_PAUSE=1 ./demo.sh   run without waiting for key presses
# AI_FALLBACK=1 ./demo.sh step4
#                        create the Store Hours fragment from the cached agent
#                        run instead of launching Claude Code
#

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

source "$DIR/lib.sh"

LIBRARY="$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC"

title() {
	printf '\n\033[1;36m══════ %s ══════\033[0m\n\n' "$*"
}

say() {
	printf '%s\n' "$*"
}

point() {
	printf '  \033[1m•\033[0m %s\n' "$*"
}

# ui TEXT [URL...]
ui() {
	printf '\033[1;35mIn the UI:\033[0m %s\n' "$1"

	shift

	local url

	for url in "$@"; do
		printf '  \033[4;34m%s\033[0m\n' "$url"
	done

	printf '\n'
}

DL_PORTLET=com_liferay_design_library_web_internal_portlet_DesignLibraryAdminPortlet
FRAGMENT_PORTLET=com_liferay_fragment_web_portlet_FragmentPortlet
MCP_PORTLET=com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet

library_field() {
	api GET "$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries/$DESIGN_LIBRARY_ERC" | jq -r ".$1"
}

library_url() {
	printf '%s/group/control_panel/manage?p_p_id=%s&p_p_lifecycle=0&p_p_state=maximized&_%s_mvcRenderCommandName=%%2Fdesign_library%%2Fview_resources_design_library&_%s_designLibraryEntryId=%s' \
		"$LIFERAY_URL" "$DL_PORTLET" "$DL_PORTLET" "$DL_PORTLET" "$(library_field id)"
}

# fragment_set_url [resources]
fragment_set_url() {
	local url

	url=$(printf '%s/group%s/~/control_panel/manage/-/fragments/fragment_collections?_%s_fragmentCollectionExternalReferenceCode=%s' \
		"$LIFERAY_URL" "$(library_field friendlyURL)" "$FRAGMENT_PORTLET" "$FRAGMENT_SET_ERC")

	if [ "${1:-}" = resources ]; then
		url="$url&_${FRAGMENT_PORTLET}_tabs1=resources"
	fi

	printf '%s' "$url"
}

mcp_tools_url() {
	printf '%s/group/control_panel/manage?p_p_id=%s&p_p_lifecycle=0&p_p_state=maximized&_%s_mvcRenderCommandName=%%2Fmcp_server%%2Fedit_profile&_%s_profileERC=devcon&_%s_tab=tools' \
		"$LIFERAY_URL" "$MCP_PORTLET" "$MCP_PORTLET" "$MCP_PORTLET" "$MCP_PORTLET"
}

library_list_url() {
	printf '%s/group/control_panel/manage?p_p_id=%s' "$LIFERAY_URL" "$DL_PORTLET"
}

store_pages_admin_urls() {
	local site

	for site in "${SITE_ERCS[@]}"; do
		printf '%s\n' "$LIFERAY_URL/group$(site_friendly_url "$site")/~/control_panel/manage?p_p_id=com_liferay_layout_admin_web_portlet_GroupPagesPortlet"
	done
}

store_urls() {
	local site

	for site in "${SITE_ERCS[@]}"; do
		printf '%s\n' "$LIFERAY_URL/web$(site_friendly_url "$site")/store-home"
	done
}

note() {
	printf '\033[2m%s\033[0m\n' "$*"
}

wait_key() {
	[ -n "${NO_PAUSE:-}" ] && return

	printf '\n\033[2m[ press any key to %s ]\033[0m' "$1"
	read -rsn1 _ < /dev/tty
	printf '\r\033[K'
}

show_file() {
	note "── ${1#$DIR/}"
	sed 's/^/    /' "$1"
}

LAST=""

# request METHOD URL [BODY] [RESPONSE_FILTER] [BODY_FILTER]
request() {
	local method="$1" url="$2" body="${3:-}" filter="${4:-.}" body_filter="${5:-.}"

	printf '\n\033[1;33m%s\033[0m \033[1m%s\033[0m\n' "$method" "${url#$LIFERAY_URL}"

	if [ -n "$body" ]; then
		jq -C "($body_filter) | (.. | objects | select(has(\"fileBase64\")) | .fileBase64) |= (.[0:40] + \"...\")" <<< "$body"

		[ "$body_filter" != "." ] && note "(request body summarized for display)"
	fi

	wait_key "send the request"

	local args=(--silent --write-out '\n%{http_code}' --user "$LIFERAY_AUTH" --request "$method" --header 'Accept: application/json, text/event-stream')

	if [ -n "$body" ]; then
		args+=(--header 'Content-Type: application/json' --data-binary "$body")
	elif [ "$method" = POST ] || [ "$method" = PUT ]; then
		args+=(--header 'Content-Type: application/json' --data-binary '{}')
	fi

	local start output

	start=$(date +%s%N)
	output=$(curl "${args[@]}" "$url")

	local elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
	local status="${output##*$'\n'}"

	LAST="${output%$'\n'*}"

	if [[ "$status" == 2* ]]; then
		printf '\033[1;32m← HTTP %s\033[0m \033[2m(%s ms)\033[0m\n' "$status" "$elapsed"
	else
		printf '\033[1;31m← HTTP %s\033[0m \033[2m(%s ms)\033[0m\n' "$status" "$elapsed"
	fi

	[ -z "$LAST" ] && return

	jq -C "$filter" <<< "$LAST" 2> /dev/null || printf '%s\n' "$LAST"

	[ "$filter" != "." ] && note "(response trimmed to the relevant fields)"
}

stores() {
	say ""
	say "What the stores show right now (rendered pages, as a guest):"

	local site

	for site in "${SITE_ERCS[@]}"; do
		printf '  %-12s %s\n' "$site" "$(page_promo "$site")"
	done
}

FRAGMENT_RESPONSE='{externalReferenceCode, key, name, type, versions: [.fragmentVersions[] | {status, fields: [.configuration.fieldSets[]?.fields[] | "\(.name) (\(.type)) = \(.defaultValue.value)"]}]}'
FRAGMENT_BODY='.fragmentVersions |= map(.html |= (.[0:70] + "...") | .css |= (.[0:40] + "..."))'

step0() {
	title "0. The starting point"
	ui "Applications Menu > Design Libraries: Acme Design Library. Open it: Connected Sites (2), and no design assets yet." "$(library_list_url)" "$(library_url)"
	ui "Site Builder > Pages of each store: no pages yet." $(store_pages_admin_urls)

	say "Acme Coffee runs one Liferay site per store. Every store is connected to one design library. Today the library is empty and the stores have no home page."
	point "Every call uses Basic authentication as test@liferay.com."
	point "Everything is addressed by external reference code (ERC): the library is acme-design-library, the stores are acme-madrid and acme-lisbon."

	request GET "$LIFERAY_URL/o/headless-admin-user/v1.0/my-user-account" "" '{emailAddress, name}'

	request GET "$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries/$DESIGN_LIBRARY_ERC/connected-sites" "" '[.items[] | {externalReferenceCode, name}]'

	request GET "$LIBRARY/fragment-sets" "" '{totalCount, items: [.items[] | {externalReferenceCode, name}]}'
}

step1() {
	title "1. A fragment set in the design library"
	ui "Acme Design Library > Design Assets. Refresh it after the request: the Acme Campaigns set appears." "$(library_url)"

	point "New: the design library paths now accept writes. Before, they could only read and delete fragment sets."
	point "PUT by ERC creates the set when it does not exist and updates it when it does."

	request PUT "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC" '{"description": "Seasonal campaigns shared by every store", "name": "Acme Campaigns"}' '{externalReferenceCode, key, name, description}'
}

step2() {
	title "2. A resource: the campaign image"
	ui "Acme Campaigns > Resources. Refresh it after the request: autumn-cup.svg appears." "$(fragment_set_url resources)"

	point "Resources are files that belong to the fragment set. The image travels as Base64 inside the JSON."
	point "Its ERC (autumn-cup.svg) is what the fragment HTML references as [resources:autumn-cup.svg]."

	request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/autumn-cup.svg")" '{externalReferenceCode, name, fragmentSetExternalReferenceCode}'
}

step3() {
	title "3. The Seasonal Promo fragment"
	ui "Acme Campaigns > Fragments. Refresh it after the request: Seasonal Promo appears, with its preview. Open it to see the HTML, CSS and configuration." "$(fragment_set_url)"

	say "The fragment is plain files: HTML, CSS and a configuration."
	say ""
	show_file "$DIR/payloads/seasonal-promo/autumn/index.html"
	say ""
	point "data-lfr-editable-id marks the texts a marketer can edit on each page."
	point "\${configuration.accentColor} and \${configuration.ctaLabel} read the configuration fields."
	point "One Approved version: it is published as soon as it is created."

	request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(fragment_payload autumn configuration.json)" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
}

step4() {
	title "4. An AI agent creates the next fragment"
	ui "MCP Server > devcon > Tools: the 8 tools the agent gets, picked from the tool sets of each headless API." "$(mcp_tools_url)"
	ui "Acme Campaigns > Fragments. Refresh it when the agent is done: Store Hours appears next to Seasonal Promo." "$(fragment_set_url)"

	point "Liferay's MCP server turns every headless API into tools an AI can call: the tool schemas are generated from the OpenAPI."
	point "The devcon profile exposes 8 of them. This is what the agent sees:"

	request POST "$LIFERAY_URL/o/mcp/devcon" '{"id": 1, "jsonrpc": "2.0", "method": "tools/list"}' '[.result.tools[] | {name, description: (.description | split("\n")[0] | split(". ")[0])}]'

	say ""
	say "The prompt:"
	say ""
	fold -s -w 100 "$DIR/demo/02-prompt.txt" | sed 's/^/    /'

	if [ -n "${AI_FALLBACK:-}" ]; then
		say ""
		note "AI_FALLBACK: creating the fragment from the cached agent run instead."

		request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(cat "$DIR/payloads/store-hours.json")" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
	else
		say ""
		point "Claude Code starts with the prompt prefilled and only the Liferay tools available. Exit it (/exit or Ctrl+D) to come back here."

		wait_key "launch Claude Code"

		"$DIR/demo/02-ai-fragment.sh"

		say ""
		say "What the agent created:"

		request GET "$LIBRARY/fragments/$HOURS_FRAGMENT_ERC" "" "$FRAGMENT_RESPONSE"
	fi
}

step5() {
	title "5. Compose the store pages with the Pages API"
	ui "The store pages: they 404 until the requests below. Refresh them afterwards, side by side." $(store_urls)
	ui "Site Builder > Pages of each store. Refresh after the requests: Store Home appears." $(store_pages_admin_urls)

	local fragments=("$PROMO_FRAGMENT_ERC")

	if library_fragment_exists "$HOURS_FRAGMENT_ERC"; then
		fragments+=("$HOURS_FRAGMENT_ERC")
	fi

	point "A page keeps its own copy of every fragment it shows: the HTML, CSS, JS and configuration. Propagation, in step 7, is what refreshes that copy."
	point "So first we read each fragment from the design library:"

	local erc

	for erc in "${fragments[@]}"; do
		request GET "$LIBRARY/fragments/$erc" "" '{externalReferenceCode, name, approved: [.fragmentVersions[] | select(.status == "Approved") | {html: (.html[0:70] + "..."), css: (.css[0:40] + "..."), fields: [.configuration.fieldSets[]?.fields[] | .name]}]}'
	done

	say ""
	point "Then one PUT per store creates its Store Home page with: ${fragments[*]}."
	point "Each element carries the fragment's content plus a reference to it (ERC and scope: the design library). The reference is what lets propagation find these pages later."
	point "The configuration goes as the JSON string fragments are stored with, where a default is the plain value instead of {\"value\": ...}."
	point "A content page has a published specification and its draft; both list the same elements."

	local site

	for site in "${SITE_ERCS[@]}"; do
		say ""
		say "── $site"

		request PUT "$SITE_API/sites/$site/site-pages/store-home" "$(page_payload "${fragments[@]}")" '{externalReferenceCode, type, friendlyUrlPath_i18n, pageSpecifications: [.pageSpecifications[] | {externalReferenceCode, status}]}' '.pageSpecifications |= [.[0] | .pageExperiences[].pageElements[].pageElementDefinition.fragmentInstance |= (.html |= (.[0:60] + "...") | .css |= (.[0:40] + "...") | .configuration |= (.[0:60] + "...")), "(the draft specification store-home-draft repeats the same elements, with a -draft suffix)"]'
	done

	stores
}

step6() {
	title "6. The winter campaign, in the design library only"
	ui "Acme Campaigns > Fragments: Seasonal Promo becomes the winter version (refresh after the PUT)." "$(fragment_set_url)"
	ui "The store pages: refresh them after the PUT. They still show autumn." $(store_urls)

	point "A new image for the set, then a PUT of the fragment with the winter HTML, CSS and accent color."

	request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/winter-cup.svg")" '{externalReferenceCode, name}'

	say ""
	note "What changes in the HTML:"
	diff "$DIR/payloads/seasonal-promo/autumn/index.html" "$DIR/payloads/seasonal-promo/winter/index.html" | grep -E '^[<>]' | sed -E 's/^</  -/; s/^>/  +/; s/data-lfr-editable[^>]*//g; s/\t+/ /g'

	request PUT "$LIBRARY/fragments/$PROMO_FRAGMENT_ERC" "$(fragment_payload winter winter-configuration.json)" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"

	say ""
	point "Pages keep their own copy of the fragment, so nothing changed for the stores yet:"

	stores
}

step7() {
	title "7. One call, every store"
	ui "The store pages: refresh them after the propagate. Winter, with the new image and color." $(store_urls)

	point "New: POST .../fragments/{erc}/propagate updates every page that uses the fragment, in the library and in every site connected to it."

	request POST "$LIBRARY/fragments/$PROMO_FRAGMENT_ERC/propagate" "" '{externalReferenceCode, name}'

	stores
}

reset() {
	local site

	for site in "${SITE_ERCS[@]}"; do
		api DELETE "$SITE_API/sites/$site/site-pages/store-home" > /dev/null 2>&1
	done

	api DELETE "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC" > /dev/null 2>&1

	echo "reset done: $(api GET "$LIBRARY/fragment-sets" | jq -r .totalCount) fragment sets in the library, no store pages"
}

if [ $# -gt 0 ]; then
	"$1"
else
	for s in step0 step1 step2 step3 step4 step5 step6 step7; do
		"$s"
		wait_key "continue to the next step"
	done

	title "Done"
fi
