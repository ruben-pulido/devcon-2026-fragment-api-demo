#!/usr/bin/env bash
# Measures propagation at scale: N extra store sites connected to the design
# library, each with a store page using the Seasonal Promo fragment.
#
#   setup/90-scale-test.sh create 100
#   setup/90-scale-test.sh measure
#   setup/90-scale-test.sh delete 100

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

action="${1:?create, measure or delete}"
count="${2:-100}"

site_erc() {
	printf 'acme-store-%04d' "$1"
}

case "$action" in
	create)
		start=$SECONDS

		for i in $(seq 1 "$count"); do
			site="$(site_erc "$i")"

			api PUT "$SITE_API/sites/$site" \
				"{\"externalReferenceCode\": \"$site\", \"name\": \"Acme Coffee Store $i\"}" >/dev/null
			api PUT "$LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries/$DESIGN_LIBRARY_ERC/connected-sites/$site" \
				'{"searchable": true}' >/dev/null
			api PUT "$SITE_API/sites/$site/site-pages/store-home" \
				"$(page_payload "$PROMO_FRAGMENT_ERC")" >/dev/null

			if (( i % 10 == 0 )); then
				echo "  $i sites ($((SECONDS - start)) s)"
			fi
		done
		;;
	measure)
		LIBRARY="$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC"

		for season in autumn winter; do
			configuration=configuration.json

			if [ "$season" = winter ]; then
				configuration=winter-configuration.json
			fi

			api PUT "$LIBRARY/fragments/$PROMO_FRAGMENT_ERC" "$(fragment_payload "$season" "$configuration")" >/dev/null

			start="$(date +%s.%N)"

			api POST "$LIBRARY/fragments/$PROMO_FRAGMENT_ERC/propagate" >/dev/null

			printf '  propagate %s: %.2f s\n' "$season" "$(echo "$(date +%s.%N) - $start" | bc)"
		done
		;;
	delete)
		for i in $(seq 1 "$count"); do
			api DELETE "$SITE_API/sites/$(site_erc "$i")" >/dev/null || true
		done
		;;
esac
