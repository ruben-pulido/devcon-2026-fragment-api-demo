# Sourced by every script in this repository.

LIFERAY_URL="${LIFERAY_URL:-http://localhost:8080}"
LIFERAY_AUTH="${LIFERAY_AUTH:-test@liferay.com:test}"

DESIGN_LIBRARY_ERC="${DESIGN_LIBRARY_ERC:-acme-design-library}"
FRAGMENT_SET_ERC="${FRAGMENT_SET_ERC:-acme-fragments}"
PROMO_FRAGMENT_ERC="${PROMO_FRAGMENT_ERC:-acme-seasonal-promo}"
HOURS_FRAGMENT_ERC="${HOURS_FRAGMENT_ERC:-acme-store-hours}"
SITE_ERCS=(${SITE_ERCS:-acme-madrid acme-lisbon})

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FRAGMENT_API="$LIFERAY_URL/o/headless-admin-fragment/v1.0"
SITE_API="$LIFERAY_URL/o/headless-admin-site/v1.0"

# api METHOD URL [JSON_BODY_FILE_OR_STRING]
# Prints the response body. On HTTP errors prints the status and body to
# stderr and returns 1, so scripts fail loudly on stage instead of silently.
api() {
	local method="$1" url="$2" body="${3:-}"
	local args=(-sS -u "$LIFERAY_AUTH" -X "$method" -H 'Accept: application/json' -w '\n%{http_code}')

	if [ -n "$body" ]; then
		if [ -f "$body" ]; then
			args+=(-H 'Content-Type: application/json' --data-binary "@$body")
		else
			args+=(-H 'Content-Type: application/json' --data-binary "$body")
		fi
	elif [ "$method" = POST ] || [ "$method" = PUT ] || [ "$method" = PATCH ]; then
		args+=(-H 'Content-Type: application/json' --data-binary '{}')
	fi

	local response status
	response="$(curl "${args[@]}" "$url")" || return 1
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

# fragment_payload SEASON CONFIGURATION_FILE
# Builds the Fragment JSON from the files under payloads/seasonal-promo.
fragment_payload() {
	local dir="$ROOT_DIR/payloads/seasonal-promo"

	jq -n \
		--arg css "$(cat "$dir/$1/index.css")" \
		--arg erc "$PROMO_FRAGMENT_ERC" \
		--arg html "$(cat "$dir/$1/index.html")" \
		--slurpfile configuration "$dir/$2" \
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
			type: "BasicFragment"
		}'
}

# resource_payload FILE
resource_payload() {
	jq -n \
		--arg base64 "$(base64 -w0 "$1")" \
		--arg name "$(basename "$1")" \
		'{externalReferenceCode: $name, fileURLReference: {fileBase64: $base64}, name: $name}'
}

# site_friendly_url SITE_ERC
site_friendly_url() {
	api GET "$SITE_API/sites/$1" | jq -r '.friendlyUrlPath'
}

# page_promo SITE_ERC
# Prints the promo title rendered on the store page of the site, as a guest.
page_promo() {
	curl -sS "$LIFERAY_URL/web$(site_friendly_url "$1")/store-home" |
		grep -oE 'acme-promo__title"[^>]*>[^<]*' | sed -E 's/.*>//'
}

show_sites() {
	for site in "${SITE_ERCS[@]}"; do
		printf '  %-12s %s\n' "$site" "$(page_promo "$site")"
	done
}

# page_payload FRAGMENT_ERC...
# Builds the store-home content page with one design library fragment per
# argument, in order, in both the published specification and its draft.
page_payload() {
	jq -n \
		--arg library "$DESIGN_LIBRARY_ERC" \
		--args \
		'
		def elements($suffix):
			[
				$ARGS.positional | to_entries[] |
				{
					externalReferenceCode: "store-home-\(.value)\($suffix)",
					pageElementDefinition: {
						fragmentInstance: {
							fragmentReference: {
								externalReferenceCode: .value,
								fragmentReferenceType: "FragmentItemExternalReference",
								scope: {externalReferenceCode: $library, type: "AssetLibrary"}
							}
						},
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
				specification("store-home-draft"; "Draft"; "-draft")
			],
			type: "ContentPage"
		}' "$@"
}

# library_fragment_exists FRAGMENT_ERC
library_fragment_exists() {
	api GET "$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC/fragments/$1" >/dev/null 2>&1
}
