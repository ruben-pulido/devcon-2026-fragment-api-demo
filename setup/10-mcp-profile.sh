#!/usr/bin/env bash
# Pre-show setup: the "devcon" profile of Liferay's MCP server, with the tools
# the agent needs on stage. Idempotent: every call is a PUT by external
# reference code.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

PROFILE_ERC="devcon"

TOOLS=(
	headless-admin-fragment-v1.0:getDesignLibraryFragment
	headless-admin-fragment-v1.0:getDesignLibraryFragmentSetFragmentsPage
	headless-admin-fragment-v1.0:postDesignLibraryFragmentPropagate
	headless-admin-fragment-v1.0:postDesignLibraryFragmentSetFragment
	headless-admin-fragment-v1.0:putDesignLibraryFragment
	headless-admin-site-v1.0:getSiteSitePage
	headless-admin-site-v1.0:putSiteSitePage
	headless-asset-library-v1.0:getAssetLibraryConnectedSitesPage
)

step "MCP profile $PROFILE_ERC"

profile_id="$(
	api PUT "$LIFERAY_URL/o/mcp/server-profiles/by-external-reference-code/$PROFILE_ERC" \
		"$(jq -n \
			--arg erc "$PROFILE_ERC" \
			--rawfile instructions "$ROOT_DIR/mcp/instructions.md" \
			'{
				description: "Devcon 2026: fragments of the Acme design library and the store pages that use them.",
				externalReferenceCode: $erc,
				instructions: $instructions,
				name: $erc,
				profileStatus: "inactive"
			}')" |
		jq -r '.id'
)"

echo "  id $profile_id"

step "Tools"

for tool in "${TOOLS[@]}"; do
	tool_set="${tool%%:*}"
	tool_name="${tool##*:}"

	api PUT "$LIFERAY_URL/o/mcp/server-profile-tools/by-external-reference-code/$PROFILE_ERC-$tool_name" \
		"$(jq -n \
			--arg erc "$PROFILE_ERC-$tool_name" \
			--argjson profileId "$profile_id" \
			--arg toolName "$tool_name" \
			--arg toolSetName "$tool_set" \
			'{
				externalReferenceCode: $erc,
				r_mcpServerProfileToTools_l_mcpServerProfileId: $profileId,
				toolName: $toolName,
				toolSetName: $toolSetName
			}')" >/dev/null

	echo "  $tool_set $tool_name"
done

step "Activate"

api PATCH "$LIFERAY_URL/o/mcp/server-profiles/by-external-reference-code/$PROFILE_ERC" \
	'{"profileStatus": "active"}' | jq -r '"  \(.profileStatus.key)"'

step "Tools the agent sees at $LIFERAY_URL/o/mcp/$PROFILE_ERC"

curl -sS -u "$LIFERAY_AUTH" -X POST \
	-H 'Accept: application/json, text/event-stream' \
	-H 'Content-Type: application/json' \
	-d '{"id": 1, "jsonrpc": "2.0", "method": "tools/list"}' \
	"$LIFERAY_URL/o/mcp/$PROFILE_ERC" |
	jq -r '.result.tools[].name' | sed 's/^/  /'
