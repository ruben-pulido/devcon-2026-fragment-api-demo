#!/usr/bin/env bash
# The "devcon" profile of Liferay's MCP server, with the tools the agent
# needs. The demo creates it in act 4 and ./demo.sh reset removes it; this
# script creates it outside the demo, to rehearse the agent on its own.
# Idempotent: every call is a PUT by external reference code.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

step "MCP profile $MCP_PROFILE_ERC"

profile_id=$(api PUT "$MCP_API/server-profiles/by-external-reference-code/$MCP_PROFILE_ERC" "$(mcp_profile_payload)" | jq -r '.id')

echo "  id $profile_id"

step "Tools"

for tool in "${MCP_TOOLS[@]}"; do
	api PUT "$MCP_API/server-profile-tools/by-external-reference-code/$MCP_PROFILE_ERC-${tool##*:}" "$(mcp_tool_payload "$profile_id" "$tool")" > /dev/null

	echo "  ${tool%%:*} ${tool##*:}"
done

for erc in $(
	api GET "$MCP_API/server-profile-tools?pageSize=-1" |
		jq -r --argjson profileId "$profile_id" '.items[] | select(.r_mcpServerProfileToTools_l_mcpServerProfileId == $profileId) | .externalReferenceCode'
); do
	if [[ " ${MCP_TOOLS[*]##*:} " != *" ${erc#"$MCP_PROFILE_ERC-"} "* ]]; then
		api DELETE "$MCP_API/server-profile-tools/by-external-reference-code/$erc" > /dev/null

		echo "  removed ${erc#"$MCP_PROFILE_ERC-"}"
	fi
done

step "Activate"

api PATCH "$MCP_API/server-profiles/by-external-reference-code/$MCP_PROFILE_ERC" '{"profileStatus": "active"}' | jq -r '"  \(.profileStatus.key)"'

step "Tools the agent sees at $MCP_API/$MCP_PROFILE_ERC"

curl -sS -u "$LIFERAY_AUTH" -X POST \
	-H 'Accept: application/json, text/event-stream' \
	-H 'Content-Type: application/json' \
	-d '{"id": 1, "jsonrpc": "2.0", "method": "tools/list"}' \
	"$MCP_API/$MCP_PROFILE_ERC" |
	jq -r '.result.tools[].name' | sed 's/^/  /'
