# Sourced by every script in this repository.

LIFERAY_URL="${LIFERAY_URL:-http://localhost:8080}"
LIFERAY_AUTH="${LIFERAY_AUTH:-test@liferay.com:test}"

DESIGN_LIBRARY_ERC="${DESIGN_LIBRARY_ERC:-rays-design-library}"
FRAGMENT_SET_ERC="${FRAGMENT_SET_ERC:-rays-campaigns}"
RESOURCE_FOLDER_ERC="${RESOURCE_FOLDER_ERC:-images}"
PROMO_FRAGMENT_ERC="${PROMO_FRAGMENT_ERC:-rays-seasonal-promo}"
HOURS_FRAGMENT_ERC="${HOURS_FRAGMENT_ERC:-rays-store-hours}"
MADRID_ERC="${MADRID_ERC:-rays-madrid}"
LONDON_ERC="${LONDON_ERC:-rays-london}"
# Every city that has hosted DevCon, in order: YEAR|SITE_ERC|CITY|ACCENT|ADDRESS
DEVCON_CITIES=(
	"2013|rays-berlin|Berlin|#ff6b6b|Unter den Linden 21, Berlin"
	"2014|rays-darmstadt|Darmstadt|#b38cff|Luisenplatz 5, Darmstadt"
	"2017|rays-amsterdam|Amsterdam|#4dd4ac|Damrak 70, Amsterdam"
	"2019|rays-mainz|Mainz|#ff7eb6|Markt 12, Mainz"
	"2023|rays-porto|Porto|#00c2d1|Rua de Santa Catarina 112, Porto"
	"2024|rays-budapest|Budapest|#9be15d|Andrássy út 34, Budapest"
	"2025|$MADRID_ERC|Madrid|#f2b84b|Calle de Alcalá 42, Madrid"
	"2026|$LONDON_ERC|London|#7cc4ff|221 Baker Street, London"
)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FRAGMENT_API="$LIFERAY_URL/o/headless-admin-fragment/v1.0"
SITE_API="$LIFERAY_URL/o/headless-admin-site/v1.0"

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
# Builds the Fragment JSON from the files under payloads/seasonal-promo.
fragment_payload() {
	local dir="$ROOT_DIR/payloads/seasonal-promo"

	jq -n \
		--arg css "$(cat "$dir/$1/index.css")" \
		--arg erc "$PROMO_FRAGMENT_ERC" \
		--arg html "$(cat "$dir/$1/index.html")" \
		--slurpfile configuration "$dir/$2" \
		--argjson thumbnail "$(thumbnail "seasonal-promo-$1.jpg")" \
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
			name: "Seasonal Promo",
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

# page_promo SITE_ERC
# Prints the promo title rendered on the store page of the site, as a guest.
page_promo() {
	curl -sS "$LIFERAY_URL/web$(site_friendly_url "$1")/store-home" |
		grep -oE 'rays-promo__title"[^>]*>[^<]*' | sed -E 's/.*>//'
}

site_exists() {
	api GET "$SITE_API/sites/$1" >/dev/null 2>&1
}

show_sites() {
	local city site year

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r year site city _ _ <<< "$city"

		if site_exists "$site"; then
			printf '  %s %-10s %s\n' "$year" "$city" "$(page_promo "$site")"
		fi
	done
}

# fragment_instance FRAGMENT_URL
# The content a page element needs for a fragment: the HTML, CSS, JS and
# configuration of its approved version, read from FRAGMENT_URL (a site or a
# design library fragment). The Pages API stores a copy of them in the page;
# propagation later refreshes that copy. The page expects the configuration as
# a JSON string in the format fragments store it, where a field's default is
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
# Builds the store-home content page with one fragment per argument, in order,
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
					externalReferenceCode: "store-home-\(.value.erc)\($suffix)",
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
			externalReferenceCode: "store-home",
			friendlyUrlPath_i18n: {en_US: "/store-home"},
			name_i18n: {en_US: "Store Home"},
			pageSettings: {type: "ContentPageSettings"},
			pageSpecifications: [
				specification("store-home"; "Approved"; "") +
					{draftContentPageSpecificationExternalReferenceCode: "store-home-draft"},
				specification("store-home-draft"; "Approved"; "-draft")
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
# The Store Header fragment of one store: its city, image and accent color.
header_payload() {
	local dir="$ROOT_DIR/payloads/store-header"

	jq -n \
		--arg css "$(cat "$dir/index.css")" \
		--arg html "$(sed -e "s|@CITY@|$1|g" -e "s|@IMAGE@|$2|g" -e "s|@ACCENT@|$3|g" -e "s|@TAGLINE@|$4|g" "$dir/index.html")" \
		--argjson thumbnail "$(thumbnail "store-header-${1,,}.jpg")" \
		'{
			externalReferenceCode: "rays-store-header",
			fragmentVersions: [{css: $css, html: $html, js: "", status: "Approved"}],
			icon: "home",
			name: "Store Header",
			thumbnailURLReference: $thumbnail,
			type: "BasicFragment"
		}'
}
