#!/usr/bin/env bash
# Demo 3: the store landing page of every site, composed with the Pages API
# from the fragments that live in the design library.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

fragments=("$PROMO_FRAGMENT_ERC")

if library_fragment_exists "$HOURS_FRAGMENT_ERC"; then
	fragments+=("$HOURS_FRAGMENT_ERC")
fi

step "Fragments on the page: ${fragments[*]}"

for site in "${SITE_ERCS[@]}"; do
	step "Store page for $site"

	api PUT "$SITE_API/sites/$site/site-pages/store-home" "$(page_payload "${fragments[@]}")" |
		jq -c '{externalReferenceCode, type, friendlyUrlPath_i18n}'

	echo "  $LIFERAY_URL/web$(site_friendly_url "$site")/store-home"
done

step "What the stores show"

show_sites
