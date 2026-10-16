#!/usr/bin/env bash
# Pre-show setup: the design library and the store sites connected to it.
# Idempotent: every call is a PUT by external reference code.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

step "Design library $DESIGN_LIBRARY_ERC"

api PUT "$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries/$DESIGN_LIBRARY_ERC" \
	"{\"externalReferenceCode\": \"$DESIGN_LIBRARY_ERC\", \"name\": \"Acme Design Library\", \"settings\": {}, \"type\": \"DesignLibrary\"}" |
	jq -c '{externalReferenceCode, name, type}'

declare -A SITE_NAMES=([acme-madrid]="Acme Coffee Madrid" [acme-lisbon]="Acme Coffee Lisbon")

for site in "${SITE_ERCS[@]}"; do
	step "Site $site, connected to $DESIGN_LIBRARY_ERC"

	api PUT "$SITE_API/sites/$site" \
		"{\"externalReferenceCode\": \"$site\", \"name\": \"${SITE_NAMES[$site]:-$site}\"}" |
		jq -c '{externalReferenceCode, name, friendlyUrlPath}'

	api PUT "$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries/$DESIGN_LIBRARY_ERC/connected-sites/$site" \
		'{"searchable": true}' >/dev/null
done

step "Connected sites"

api GET "$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries/$DESIGN_LIBRARY_ERC/connected-sites" |
	jq -r '.items[] | "  \(.externalReferenceCode)  \(.name)"'
