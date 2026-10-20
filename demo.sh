#!/usr/bin/env bash
#
# One API, Thousands of Sites: step-by-step demo
#
#   ./demo.sh            run every step, pausing before each request
#   ./demo.sh step6      run a single step (step0 ... step9)
#   ./demo.sh reset      back to the starting point: Madrid with its store header
#
# NO_PAUSE=1 ./demo.sh   run without waiting for key presses
# AI_FALLBACK=1 ./demo.sh step7
#                        create the Store Hours fragment from the cached agent
#                        run instead of launching Claude Code
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

DL_PORTLET=com_liferay_design_library_web_internal_portlet_DesignLibraryAdminPortlet
FRAGMENT_PORTLET=com_liferay_fragment_web_portlet_FragmentPortlet
MCP_PORTLET=com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet

library_field() {
	api GET "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" | jq -r ".$1"
}

library_list_url() {
	printf '%s/group/control_panel/manage?p_p_id=%s' "$LIFERAY_URL" "$DL_PORTLET"
}

library_url() {
	printf '%s/group/control_panel/manage?p_p_id=%s&p_p_lifecycle=0&p_p_state=maximized&_%s_mvcRenderCommandName=%%2Fdesign_library%%2Fview_resources_design_library&_%s_designLibraryEntryId=%s' \
		"$LIFERAY_URL" "$DL_PORTLET" "$DL_PORTLET" "$DL_PORTLET" "$(library_field id)"
}

# fragment_set_url GROUP_FRIENDLY_URL SET_ERC [resources]
fragment_set_url() {
	local url

	url=$(printf '%s/group%s/~/control_panel/manage/-/fragments/fragment_collections?_%s_fragmentCollectionExternalReferenceCode=%s' \
		"$LIFERAY_URL" "$1" "$FRAGMENT_PORTLET" "$2")

	if [ "${3:-}" = resources ]; then
		url="$url&_${FRAGMENT_PORTLET}_tabs1=resources"
	fi

	printf '%s' "$url"
}

# site_fragment_set_url SITE_ERC SET_ERC [resources]
site_fragment_set_url() {
	fragment_set_url "$(site_friendly_url "$1")" "$2" "${3:-}"
}

# library_fragment_set_url [resources]
library_fragment_set_url() {
	fragment_set_url "$(library_field friendlyURL)" "$FRAGMENT_SET_ERC" "${1:-}"
}

mcp_tools_url() {
	printf '%s/group/control_panel/manage?p_p_id=%s&p_p_lifecycle=0&p_p_state=maximized&_%s_mvcRenderCommandName=%%2Fmcp_server%%2Fedit_profile&_%s_profileERC=devcon&_%s_tab=tools' \
		"$LIFERAY_URL" "$MCP_PORTLET" "$MCP_PORTLET" "$MCP_PORTLET" "$MCP_PORTLET"
}

# store_url SITE_ERC
store_url() {
	printf '%s/web%s/store-home' "$LIFERAY_URL" "$(site_friendly_url "$1")"
}

# pages_admin_url SITE_ERC
pages_admin_url() {
	printf '%s/group%s/~/control_panel/manage?p_p_id=com_liferay_layout_admin_web_portlet_GroupPagesPortlet' "$LIFERAY_URL" "$(site_friendly_url "$1")"
}

stores() {
	say ""
	say "What the stores show right now (rendered pages, as a guest):"

	show_sites
}

FRAGMENT_RESPONSE='{externalReferenceCode, key, name, type, versions: [.fragmentVersions[] | {status, fields: [.configuration.fieldSets[]?.fields[] | "\(.name) (\(.type)) = \(.defaultValue.value)"]}]}'
FRAGMENT_BODY='.fragmentVersions |= map(.html |= (.[0:70] + "...") | .css |= (.[0:40] + "..."))'
PAGE_RESPONSE='{externalReferenceCode, type, friendlyUrlPath_i18n, pageSpecifications: [.pageSpecifications[] | {externalReferenceCode, status}]}'
PAGE_BODY='.pageSpecifications |= [.[0] | .pageExperiences[].pageElements[].pageElementDefinition.fragmentInstance |= (.html |= (.[0:60] + "...") | .css |= (.[0:40] + "...") | .configuration |= ((. // "")[0:60] + "...")), "(the draft specification store-home-draft repeats the same elements, with a -draft suffix)"]'

# put_store_page SITE_ERC SCOPE:FRAGMENT_ERC...
put_store_page() {
	local site="$1"

	shift

	request PUT "$SITE_API/sites/$site/site-pages/store-home" "$(page_payload "$@")" "$PAGE_RESPONSE" "$PAGE_BODY"
}

step0() {
	title "0. The starting point: one store in Madrid"
	ui "Madrid's own fragments: only its Store Header." "$(site_fragment_set_url "$MADRID_ERC" "$STORE_SET_ERC")"
	ui "Site Builder > Pages of Madrid: no store page yet." "$(pages_admin_url "$MADRID_ERC")"

	say "Ray’s Coffee has one store, in Madrid, with its own Liferay site. Today we build its store page with the Fragment Headless API alone."
	point "Every call uses Basic authentication as test@liferay.com."
	point "Everything is addressed by external reference code (ERC): the site is rays-madrid."

	request GET "$LIFERAY_URL/o/headless-admin-user/v1.0/my-user-account" "" '{emailAddress, name}'

	request GET "$MADRID/fragment-sets" "" '{totalCount, items: [.items[] | {externalReferenceCode, name}]}'
}

step1() {
	title "1. A fragment set in the Madrid site"
	ui "Madrid > Design > Fragments. Refresh it after the request: the Ray’s Campaigns set appears." "$(site_fragment_set_url "$MADRID_ERC" "$STORE_SET_ERC")"

	point "PUT by ERC creates the set when it does not exist and updates it when it does."

	request PUT "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" '{"description": "Seasonal campaigns", "name": "Ray’s Campaigns"}' '{externalReferenceCode, key, name, description}'
}

step2() {
	title "2. A resource: the campaign image"
	ui "Ray’s Campaigns > Resources. Refresh it after the request: autumn-cup.svg appears." "$(site_fragment_set_url "$MADRID_ERC" "$FRAGMENT_SET_ERC" resources)"

	point "Resources are files that belong to the fragment set. The image travels as Base64 inside the JSON."
	point "Its ERC (autumn-cup.svg) is what the fragment HTML references as [resources:autumn-cup.svg]."

	request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/autumn-cup.svg")" '{externalReferenceCode, name, fragmentSetExternalReferenceCode}'
}

step3() {
	title "3. The Seasonal Promo fragment"
	ui "Ray’s Campaigns > Fragments. Refresh it after the request: Seasonal Promo appears. Open it to see the HTML, CSS and configuration." "$(site_fragment_set_url "$MADRID_ERC" "$FRAGMENT_SET_ERC")"

	say "The fragment is plain files: HTML, CSS and a configuration, designed for a dark page."
	say ""
	show_file "$DIR/payloads/seasonal-promo/autumn/index.html"
	say ""
	point "data-lfr-editable-id marks the texts a marketer can edit on each page."
	point "\${configuration.accentColor} and \${configuration.ctaLabel} read the configuration fields."

	request POST "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$(fragment_payload autumn configuration.json)" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
}

step4() {
	title "4. Madrid's store page, with the Pages API"
	ui "The Madrid store page: it 404s until the PUT below. Refresh it afterwards." "$(store_url "$MADRID_ERC")"

	point "A page keeps its own copy of every fragment it shows: the HTML, CSS, JS and configuration. So first we read the fragments:"

	request GET "$MADRID/fragments/$HEADER_FRAGMENT_ERC" "" '{externalReferenceCode, name}'
	request GET "$MADRID/fragments/$PROMO_FRAGMENT_ERC" "" '{externalReferenceCode, name}'

	say ""
	point "Then one PUT creates the page. Each element carries the fragment's content plus a reference to it; a reference without scope means a fragment of the same site."

	put_store_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "$MADRID_ERC:$PROMO_FRAGMENT_ERC"

	stores
}

step5() {
	title "5. A second store opens in London"
	ui "Applications Menu > Design Libraries. Refresh it after the requests: Ray’s Design Library, connected to both stores." "$(library_list_url)"

	say "London gets its own site and its own header. The campaigns should be shared, so we create a design library and connect both stores to it."

	request PUT "$SITE_API/sites/$LONDON_ERC" "{\"externalReferenceCode\": \"$LONDON_ERC\", \"name\": \"Ray’s Coffee London\"}" '{externalReferenceCode, name, friendlyUrlPath}'

	request PUT "$LONDON/fragment-sets/$STORE_SET_ERC" '{"name": "Ray’s Store"}' '{externalReferenceCode, name}'
	request POST "$LONDON/fragment-sets/$STORE_SET_ERC/resource-files" "$(resource_payload "$DIR/assets/london-skyline.svg")" '{externalReferenceCode, name}'
	request POST "$LONDON/fragment-sets/$STORE_SET_ERC/fragments" "$(header_payload London london-skyline.svg '#7cc4ff' '221 Baker Street, London')" '{externalReferenceCode, name}' "$FRAGMENT_BODY"

	say ""
	point "The design library, then a PUT per store to connect it."

	request PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" "{\"externalReferenceCode\": \"$DESIGN_LIBRARY_ERC\", \"name\": \"Ray’s Design Library\", \"settings\": {}, \"type\": \"DesignLibrary\"}" '{externalReferenceCode, name, type}'

	local site

	for site in "$MADRID_ERC" "$LONDON_ERC"; do
		request PUT "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC/connected-sites/$site" '{"searchable": true}' '{externalReferenceCode, name}'
	done
}

step6() {
	title "6. Move the campaigns from Madrid to the design library"
	ui "The design library's Ray’s Campaigns set. Refresh it after the requests: the image and Seasonal Promo are there." "$(library_fragment_set_url)"
	ui "Madrid's fragments: after the move, only its own Store Header remains." "$(site_fragment_set_url "$MADRID_ERC" "$STORE_SET_ERC")"

	say "There is no move operation: the API copies the set, its images and its fragments into the library, repoints the pages, and removes the originals."

	request PUT "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC" '{"description": "Seasonal campaigns shared by every store", "name": "Ray’s Campaigns"}' '{externalReferenceCode, name}'

	say ""
	point "The images, read with their content (nestedFields=fileURLReference.fileBase64) and posted to the library:"

	request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/resource-files?nestedFields=fileURLReference.fileBase64" "" '[.items[] | {externalReferenceCode, name, fileBase64: ((.fileURLReference.fileBase64 // "")[0:40] + "...")}]'

	local files="$LAST" file

	while read -r file; do
		request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" "$file" '{externalReferenceCode, name}'
	done < <(jq -c '.items[] | {externalReferenceCode, fileURLReference: {fileBase64: .fileURLReference.fileBase64}, name}' <<< "$files")

	say ""
	point "The fragments, read from Madrid and posted to the library:"

	request GET "$MADRID/fragment-sets/$FRAGMENT_SET_ERC/fragments" "" '[.items[] | {externalReferenceCode, name}]'

	local fragments="$LAST" fragment

	while read -r fragment; do
		request POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" "$fragment" "$FRAGMENT_RESPONSE" "$FRAGMENT_BODY"
	done < <(jq -c '.items[] | {externalReferenceCode, fragmentVersions: [.fragmentVersions[] | select(.status == "Approved") | {configuration, css, html, js, status}], icon, name, type}' <<< "$fragments")

	say ""
	point "Both store pages now reference the library's Seasonal Promo; each keeps its own header."

	put_store_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC"
	put_store_page "$LONDON_ERC" "$LONDON_ERC:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC"

	say ""
	point "Nothing uses Madrid's copies anymore, so the set goes, with its fragments and images:"

	request DELETE "$MADRID/fragment-sets/$FRAGMENT_SET_ERC"

	stores
}

step7() {
	title "7. An AI agent creates the next fragment in the library"
	ui "MCP Server > devcon > Tools: the tools the agent gets, picked from the tool sets of each headless API." "$(mcp_tools_url)"
	ui "The design library's Ray’s Campaigns set. Refresh it when the agent is done: Store Hours appears." "$(library_fragment_set_url)"

	point "Liferay's MCP server turns every headless API into tools an AI can call: the tool schemas are generated from the OpenAPI."

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

	if library_fragment_exists "$HOURS_FRAGMENT_ERC"; then
		say ""
		point "Both store pages get it, below the promo:"

		put_store_page "$MADRID_ERC" "$MADRID_ERC:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC" "library:$HOURS_FRAGMENT_ERC"
		put_store_page "$LONDON_ERC" "$LONDON_ERC:$HEADER_FRAGMENT_ERC" "library:$PROMO_FRAGMENT_ERC" "library:$HOURS_FRAGMENT_ERC"
	fi
}

step8() {
	title "8. The winter campaign, in the design library only"
	ui "The store pages: refresh them after the PUT. They still show autumn." "$(store_url "$MADRID_ERC")" "$(store_url "$LONDON_ERC")"

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

step9() {
	title "9. Propagate to every store, from the UI"
	ui "The design library's Ray’s Campaigns set: Seasonal Promo > ⋮ > View Site Usages, select Madrid and London, then Propagate." "$(library_fragment_set_url)"
	ui "Then refresh both store pages." "$(store_url "$MADRID_ERC")" "$(store_url "$LONDON_ERC")"

	point "Propagation copies the fragment's latest version into every page that uses it, in the sites you select among those connected to the library."

	wait_key "continue once you have propagated in the UI"

	stores
}

reset() {
	local site

	for site in "$MADRID_ERC" "$LONDON_ERC"; do
		api DELETE "$SITE_API/sites/$site/site-pages/store-home" > /dev/null 2>&1
	done

	api DELETE "$ASSET_LIBRARY_API/$DESIGN_LIBRARY_ERC" > /dev/null 2>&1
	api DELETE "$SITE_API/sites/$LONDON_ERC" > /dev/null 2>&1
	api DELETE "$MADRID/fragment-sets/$FRAGMENT_SET_ERC" > /dev/null 2>&1

	echo "reset done: Madrid has $(api GET "$MADRID/fragment-sets" | jq -r .totalCount) fragment set(s), no store page; no London, no design library"
}

if [ $# -gt 0 ]; then
	"$1"
else
	for s in step0 step1 step2 step3 step4 step5 step6 step7 step8 step9; do
		"$s"
		wait_key "continue to the next step"
	done

	title "Done"
fi
