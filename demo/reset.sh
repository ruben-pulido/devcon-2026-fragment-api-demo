#!/usr/bin/env bash
# Back to the starting point of the talk: the design library and the
# connected store sites exist, with no fragments and no store pages.

set -uo pipefail

source "$(dirname "$0")/../lib.sh"

for site in "${SITE_ERCS[@]}"; do
	step "Delete the store page of $site"

	api DELETE "$SITE_API/sites/$site/site-pages/store-home" >/dev/null && echo "  deleted"
done

step "Delete the fragment set $FRAGMENT_SET_ERC, with its fragments and resources"

api DELETE "$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC/fragment-sets/$FRAGMENT_SET_ERC" >/dev/null && echo "  deleted"

step "What is left in the design library"

api GET "$FRAGMENT_API/design-libraries/$DESIGN_LIBRARY_ERC/fragment-sets" |
	jq -r '"  \(.totalCount) fragment sets"'
