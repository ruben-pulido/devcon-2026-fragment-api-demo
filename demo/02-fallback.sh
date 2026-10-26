#!/usr/bin/env bash
# Demo 2 fallback: the Breakfast Hours fragment from a cached agent run.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

step "Breakfast Hours, from the cached payload"

api POST "$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC/fragment-sets/$FRAGMENT_SET_ERC/fragments" \
	"$ROOT_DIR/payloads/breakfast-hours.json" |
	jq -c '{externalReferenceCode, name, type}'
