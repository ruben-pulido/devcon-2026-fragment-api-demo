#!/usr/bin/env bash
# Pre-show setup: the Madrid store site with its own Store Header fragment.
# London and the design library are created during the demo (act 2).
# Idempotent: every call is a PUT by external reference code.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

MADRID="$FRAGMENT_API/sites/$MADRID_ERC"

step "Site $MADRID_ERC"

api PUT "$SITE_API/sites/$MADRID_ERC" \
	"{\"externalReferenceCode\": \"$MADRID_ERC\", \"name\": \"Ray’s Coffee Madrid\"}" |
	jq -c '{externalReferenceCode, name, friendlyUrlPath}'

step "Madrid's own fragment set, header image and Store Header"

api PUT "$MADRID/fragment-sets/rays-store" '{"name": "Ray’s Store"}' | jq -c '{externalReferenceCode, name}'

api PUT "$MADRID/resource-files/madrid-ray.png" \
	"$(resource_payload "$ROOT_DIR/assets/madrid-ray.png" | jq -c '. + {fragmentSetExternalReferenceCode: "rays-store"}')" |
	jq -c '{externalReferenceCode, name}'

api PUT "$MADRID/fragments/rays-store-header" \
	"$(header_payload Madrid madrid-ray.png '#f2b84b' 'Calle de Alcalá 42, Madrid' | jq -c '. + {fragmentSetExternalReferenceCode: "rays-store"}')" |
	jq -c '{externalReferenceCode, name}'
