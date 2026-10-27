# Sourced by every script in this repository.

LIFERAY_URL="${LIFERAY_URL:-http://localhost:8080}"
LIFERAY_AUTH="${LIFERAY_AUTH:-test@liferay.com:test}"

DESIGN_LIBRARY_ERC="${DESIGN_LIBRARY_ERC:-rays-design-library}"
FRAGMENT_SET_ERC="${FRAGMENT_SET_ERC:-rays-campaigns}"
RESOURCE_FOLDER_ERC="${RESOURCE_FOLDER_ERC:-images}"
OFFER_FRAGMENT_ERC="${OFFER_FRAGMENT_ERC:-rays-seasonal-offer}"
BREAKFAST_FRAGMENT_ERC="${BREAKFAST_FRAGMENT_ERC:-rays-breakfast-hours}"
MADRID_ERC="${MADRID_ERC:-rays-madrid}"
LONDON_ERC="${LONDON_ERC:-rays-london}"
MCP_PROFILE_ERC="${MCP_PROFILE_ERC:-devcon}"
MCP_API="$LIFERAY_URL/o/mcp"

# The agent's Claude Code tools: only the MCP server's, none of its own.
AGENT_ALLOWED_TOOLS="mcp__liferay"
AGENT_DISALLOWED_TOOLS="Agent Bash Edit Glob Grep NotebookEdit Read Skill Task WebFetch WebSearch Write"

# mcp_config [AUTHORIZATION]: the agent's MCP configuration, Liferay's MCP
# server only, at the devcon profile. AUTHORIZATION replaces the real
# credentials, to show it.
mcp_config() {
	jq -n \
		--arg authorization "${1:-Basic $(printf '%s' "$LIFERAY_AUTH" | base64 -w0)}" \
		--arg url "$MCP_API/$MCP_PROFILE_ERC" \
		'{mcpServers: {liferay: {type: "http", url: $url, headers: {Authorization: $authorization}}}}'
}

# The tools of the agent's MCP profile: TOOL_SET:TOOL.
MCP_TOOLS=(
	headless-admin-fragment-v1.0:getDesignLibraryFragment
	headless-admin-fragment-v1.0:getDesignLibraryFragmentSetFragmentsPage
	headless-admin-fragment-v1.0:postDesignLibraryFragmentSetFragment
	headless-admin-fragment-v1.0:putDesignLibraryFragment
	headless-admin-site-v1.0:getSiteSitePage
	headless-admin-site-v1.0:putSiteSitePage
	headless-asset-library-v1.0:getAssetLibraryConnectedSitesPage
)

# mcp_profile_payload: the agent's MCP profile, inactive until its tools are
# in place, with the instructions in mcp/instructions.md.
mcp_profile_payload() {
	jq -n \
		--arg erc "$MCP_PROFILE_ERC" \
		--rawfile instructions "$ROOT_DIR/mcp/instructions.md" \
		'{
			description: "Devcon 2026: fragments of the Ray’s Hotels design library and the hotel pages that use them.",
			externalReferenceCode: $erc,
			instructions: $instructions,
			name: $erc,
			profileStatus: "inactive"
		}'
}

# mcp_tool_payload PROFILE_ID TOOL_SET:TOOL
mcp_tool_payload() {
	jq -n \
		--arg erc "$MCP_PROFILE_ERC-${2##*:}" \
		--argjson profileId "$1" \
		--arg toolName "${2##*:}" \
		--arg toolSetName "${2%%:*}" \
		'{
			externalReferenceCode: $erc,
			r_mcpServerProfileToTools_l_mcpServerProfileId: $profileId,
			toolName: $toolName,
			toolSetName: $toolSetName
		}'
}

# slug CITY: the city's name in the file names of its images and thumbnail.
slug() {
	local city="${1,,}"

	echo "${city// /-}"
}

# The hotels, in order: SITE_ERC|CITY|ACCENT|ADDRESS. Madrid and London come
# last: they are built by hand in acts 1 and 2. The other six are the cities
# that could host DevCon next, with their hotels opened in act 6.
DEVCON_CITIES=(
	"rays-tenerife|Tenerife|#ff8c42|Avenida de Las Américas 8, Tenerife"
	"rays-mykonos|Mykonos|#4f8dff|Matoyianni 14, Mykonos Town"
	"rays-taormina|Taormina|#d4e157|Corso Umberto 54, Taormina"
	"rays-sydney|Sydney|#b07cff|Circular Quay 1, Sydney"
	"rays-rio|Rio de Janeiro|#1fd18a|Avenida Atlântica 1702, Rio de Janeiro"
	"rays-honolulu|Honolulu|#ff5d73|Kalakaua Avenue 2005, Honolulu"
	"$MADRID_ERC|Madrid|#f2b84b|Calle de Alcalá 42, Madrid"
	"$LONDON_ERC|London|#7cc4ff|221 Baker Street, London"
)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FRAGMENT_API="$LIFERAY_URL/o/headless-admin-fragment/v1.0"
SITE_API="$LIFERAY_URL/o/headless-admin-site/v1.0"

# The admin screens and hotel pages the demo shows in the browser.
GRID_URL="http://localhost:${GRID_PORT:-8090}"
FRAGMENTS="/~/control_panel/manage/-/fragments/fragment_collections?_com_liferay_fragment_web_portlet_FragmentPortlet_fragmentCollectionExternalReferenceCode"
RESOURCES="&_com_liferay_fragment_web_portlet_FragmentPortlet_tabs1=resources"
PAGES="/~/control_panel/manage?p_p_id=com_liferay_layout_admin_web_portlet_GroupPagesPortlet"
MCP_PORTLET=com_liferay_mcp_server_web_internal_portlet_MCPServerPortlet
LIBRARY_PORTLET=com_liferay_design_library_web_internal_portlet_DesignLibraryAdminPortlet
MADRID_ADMIN="$LIFERAY_URL/group/ray-s-hotel-madrid"
LONDON_ADMIN="$LIFERAY_URL/group/ray-s-hotel-london"
MADRID_PAGE="$LIFERAY_URL/web/ray-s-hotel-madrid/hotel-home"
LONDON_PAGE="$LIFERAY_URL/web/ray-s-hotel-london/hotel-home"
SITES="$LIFERAY_URL/group/control_panel/manage?p_p_id=com_liferay_site_admin_web_portlet_SiteAdminPortlet"
LIBRARIES="$LIFERAY_URL/group/control_panel/manage?p_p_id=$LIBRARY_PORTLET"
MCP_PROFILES="$LIFERAY_URL/group/control_panel/manage?p_p_id=$MCP_PORTLET"
MCP_TOOLS_URL="$MCP_PROFILES&p_p_lifecycle=0&p_p_state=maximized&_${MCP_PORTLET}_mvcRenderCommandName=%2Fmcp_server%2Fedit_profile&_${MCP_PORTLET}_profileERC=devcon&_${MCP_PORTLET}_tab=tools"

# api METHOD URL [JSON_BODY_FILE_OR_STRING]
# Prints the response body. On HTTP errors prints the status and body to
# stderr and returns 1, so scripts fail loudly on stage instead of silently.
api() {
	local method="$1" url="$2" body="${3:-}" body_file=""
	local args=(-sS -u "$LIFERAY_AUTH" -X "$method" -H 'Accept: application/json' -w '\n%{http_code}')

	if [ -n "$body" ]; then
		if [ -f "$body" ]; then
			args+=(-H 'Content-Type: application/json' --data-binary "@$body")
		else
			body_file=$(mktemp)
			printf '%s' "$body" > "$body_file"
			args+=(-H 'Content-Type: application/json' --data-binary "@$body_file")
		fi
	elif [ "$method" = POST ] || [ "$method" = PUT ] || [ "$method" = PATCH ]; then
		args+=(-H 'Content-Type: application/json' --data-binary '{}')
	fi

	local response status
	response="$(curl "${args[@]}" "$url")"

	local curl_status=$?

	[ -n "$body_file" ] && rm -f "$body_file"

	[ $curl_status -eq 0 ] || return 1

	status="${response##*$'\n'}"
	response="${response%$'\n'*}"

	if [ "$status" -ge 300 ]; then
		echo "HTTP $status $method $url" >&2
		echo "$response" >&2
		return 1
	fi

	echo "$response"
}

step() {
	printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}

# thumbnail FILE
# A fragment thumbnail, as the thumbnailURLReference of a Fragment.
thumbnail() {
	jq -n --arg base64 "$(base64 -w0 "$ROOT_DIR/assets/thumbnails/$1")" '{fileBase64: $base64}'
}

CHROME="${CHROME:-$(command -v google-chrome || command -v chromium || command -v chromium-browser)}"

# render_thumbnail FRAGMENT_JSON OUT_FILE
# Renders the approved version of a fragment, with its configuration's
# default values, to a PNG with headless Chrome.
render_thumbnail() {
	local html

	html=$(mktemp --suffix=.html)

	jq -r '
		.fragmentVersions[] | select(.status == "Approved") |
		([.configuration.fieldSets[]?.fields[]? | {key: .name, value: (.defaultValue.value? // .defaultValue | tostring)}] | from_entries) as $defaults |
		"<!doctype html><meta charset=\"utf-8\"><body style=\"margin: 0; min-height: 100vh; display: flex; flex-direction: column; justify-content: center; background: #0b0d12;\"><style>\(.css)</style>" +
		(.html | gsub("\\$\\{configuration\\.(?<name>[A-Za-z0-9]+)[^}]*\\}"; $defaults[.name] // "")) +
		"</body>"' <<< "$1" > "$html"

	"$CHROME" --headless=new --disable-gpu --hide-scrollbars --screenshot="$2" --window-size=1000,360 "file://$html" > /dev/null 2>&1

	rm -f "$html"

	[ -s "$2" ]
}

# fragment_payload SEASON CONFIGURATION_FILE
# Builds the Fragment JSON from the files under payloads/seasonal-offer.
fragment_payload() {
	local dir="$ROOT_DIR/payloads/seasonal-offer"

	jq -n \
		--arg css "$(cat "$dir/$1/index.css")" \
		--arg erc "$OFFER_FRAGMENT_ERC" \
		--arg html "$(cat "$dir/$1/index.html")" \
		--slurpfile configuration "$dir/$2" \
		--argjson thumbnail "$(thumbnail "seasonal-offer-$1.jpg")" \
		'{
			externalReferenceCode: $erc,
			fragmentVersions: [
				{
					configuration: $configuration[0],
					css: $css,
					html: $html,
					js: "",
					status: "Approved"
				}
			],
			icon: "megaphone",
			name: "Seasonal Offer",
			thumbnailURLReference: $thumbnail,
			type: "BasicFragment"
		}'
}

# resource_payload FILE [RESOURCE_FOLDER_ERC]
resource_payload() {
	jq -n \
		--arg base64 "$(base64 -w0 "$1")" \
		--arg folder "${2:-}" \
		--arg name "$(basename "$1")" \
		'{externalReferenceCode: $name, fileURLReference: {fileBase64: $base64}, name: $name} + (if $folder == "" then {} else {resourceFolderExternalReferenceCode: $folder} end)'
}

# site_friendly_url SITE_ERC
site_friendly_url() {
	api GET "$SITE_API/sites/$1" | jq -r '.friendlyUrlPath'
}

# page_offer SITE_ERC
# Prints the offer title rendered on the hotel page of the site, as a guest.
page_offer() {
	curl -sS "$LIFERAY_URL/web$(site_friendly_url "$1")/hotel-home" |
		grep -oE 'rays-offer__title"[^>]*>[^<]*' | sed -E 's/.*>//'
}

site_exists() {
	api GET "$SITE_API/sites/$1" >/dev/null 2>&1
}

show_sites() {
	local city site

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r site city _ _ <<< "$city"

		if site_exists "$site"; then
			printf '  %-15s %s\n' "$city" "$(page_offer "$site")"
		fi
	done
}

# fragment_instance FRAGMENT_URL
# The content a page element needs for a fragment: the HTML, CSS, JS and
# configuration of its approved version, read from FRAGMENT_URL (a site or a
# design library fragment). The Pages API hotels a copy of them in the page;
# propagation later refreshes that copy. The page expects the configuration as
# a JSON string in the format fragments hotel it, where a field's default is
# the plain value instead of {"value": ...}.
fragment_instance() {
	api GET "$1" |
		jq -c '
			.fragmentVersions[] | select(.status == "Approved") |
			{
				configuration: (
					.configuration |
					.fieldSets[]?.fields[]? |= (.defaultValue |= (if type == "object" and has("value") then .value else . end)) |
					tojson
				),
				css,
				html,
				js
			}'
}

# page_payload SCOPE:FRAGMENT_ERC...
# Builds the hotel-home content page with one fragment per argument, in order,
# in both the published specification and its draft. SCOPE is "library" for a
# design library fragment, or the ERC of the page's own site for a fragment of
# that site (its reference then has no scope).
page_payload() {
	local erc item instances="[]" scope url

	for item in "$@"; do
		scope="${item%%:*}"
		erc="${item#*:}"

		if [ "$scope" = library ]; then
			url="$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC/fragments/$erc"
		else
			url="$FRAGMENT_API/sites/$scope/fragments/$erc"
		fi

		instances=$(jq -c --arg erc "$erc" --arg scope "$scope" --argjson instance "$(fragment_instance "$url")" '. + [{erc: $erc, instance: $instance, scope: $scope}]' <<< "$instances")
	done

	jq -n \
		--arg library "$DESIGN_LIBRARY_ERC" \
		--argjson instances "$instances" \
		'
		def reference:
			{externalReferenceCode: .erc, fragmentReferenceType: "FragmentItemExternalReference"} +
			(if .scope == "library" then {scope: {externalReferenceCode: $library, type: "AssetLibrary"}} else {} end);
		def elements($suffix):
			[
				$instances | to_entries[] |
				{
					externalReferenceCode: "hotel-home-\(.value.erc)\($suffix)",
					pageElementDefinition: {
						fragmentInstance: (.value.instance + {fragmentReference: (.value | reference)}),
						type: "BasicFragment"
					},
					position: .key
				}
			];
		def specification($erc; $status; $suffix):
			{
				externalReferenceCode: $erc,
				pageExperiences: [
					{
						externalReferenceCode: "\($erc)-default-experience",
						key: "DEFAULT",
						name_i18n: {en_US: "Default"},
						pageElements: elements($suffix)
					}
				],
				status: $status,
				type: "ContentPageSpecification"
			};
		{
			externalReferenceCode: "hotel-home",
			friendlyUrlPath_i18n: {en_US: "/hotel-home"},
			name_i18n: {en_US: "Hotel Home"},
			pageSettings: {type: "ContentPageSettings"},
			pageSpecifications: [
				specification("hotel-home"; "Approved"; "") +
					{draftContentPageSpecificationExternalReferenceCode: "hotel-home-draft"},
				specification("hotel-home-draft"; "Approved"; "-draft")
			],
			type: "ContentPage"
		}'
}

# library_fragment_exists FRAGMENT_ERC
library_fragment_exists() {
	api GET "$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC/fragments/$1" >/dev/null 2>&1
}

# library_exists
library_exists() {
	api GET "$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries/$DESIGN_LIBRARY_ERC" >/dev/null 2>&1
}

# header_payload CITY IMAGE ACCENT TAGLINE
# The Hotel Header fragment of one hotel: Ray in its color (CITY-ray.png),
# its city, the view from a room (IMAGE) and its accent color.
header_payload() {
	local dir="$ROOT_DIR/payloads/hotel-header"

	jq -n \
		--arg css "$(cat "$dir/index.css")" \
		--arg html "$(sed -e "s|@CITY@|$1|g" -e "s|@IMAGE@|$2|g" -e "s|@RAY@|$(slug "$1")-ray.png|g" -e "s|@ACCENT@|$3|g" -e "s|@TAGLINE@|$4|g" "$dir/index.html")" \
		--argjson thumbnail "$(thumbnail "hotel-header-$(slug "$1").jpg")" \
		'{
			externalReferenceCode: "rays-hotel-header",
			fragmentVersions: [{css: $css, html: $html, js: "", status: "Approved"}],
			icon: "home",
			name: "Hotel Header",
			thumbnailURLReference: $thumbnail,
			type: "BasicFragment"
		}'
}
