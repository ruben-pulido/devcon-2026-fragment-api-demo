#!/usr/bin/env bash
# Demo 4: one change in the design library, propagated to every store.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

LIBRARY="$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC"

step "Before"

show_sites

step "1. New campaign image in the design library"

api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" \
	"$(resource_payload "$ROOT_DIR/assets/winter-cup.svg")" |
	jq -c '{externalReferenceCode, name}'

step "2. Update the fragment: the winter campaign"

api PUT "$LIBRARY/fragments/$PROMO_FRAGMENT_ERC" \
	"$(fragment_payload winter winter-configuration.json)" |
	jq -c '{externalReferenceCode, name, versions: [.fragmentVersions[].status]}'

step "The stores still show the previous version"

show_sites

if [ -t 0 ]; then
	read -r -p $'\nPress Enter to propagate... '
fi

step "3. Propagate"

time api POST "$LIBRARY/fragments/$PROMO_FRAGMENT_ERC/propagate" | jq -c '{externalReferenceCode, name}'

step "After"

show_sites
