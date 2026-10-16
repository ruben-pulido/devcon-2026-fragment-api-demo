#!/usr/bin/env bash
# Demo 1: a fragment set, a resource and a fragment, created in the design
# library through the Fragment Headless API.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

LIBRARY="$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC"

step "1. Fragment set"

api PUT "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC" \
	'{"description": "Seasonal campaigns shared by every store", "name": "Acme Campaigns"}' |
	jq -c '{externalReferenceCode, name}'

step "2. Resource: the campaign image"

api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/resource-files" \
	"$(resource_payload "$ROOT_DIR/assets/autumn-cup.svg")" |
	jq -c '{externalReferenceCode, name}'

step "3. Fragment: Seasonal Promo"

api POST "$LIBRARY/fragment-sets/$FRAGMENT_SET_ERC/fragments" \
	"$(fragment_payload autumn configuration.json)" |
	jq -c '{externalReferenceCode, key, name, type, versions: [.fragmentVersions[].status]}'
