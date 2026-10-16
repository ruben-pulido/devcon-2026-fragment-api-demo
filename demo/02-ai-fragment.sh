#!/usr/bin/env bash
# Demo 2: an AI agent creates a fragment through Liferay's own MCP server.
#
#   demo/02-ai-fragment.sh             interactive Claude Code, prompt prefilled
#   demo/02-ai-fragment.sh --rehearse  unattended run, transcript in $TRANSCRIPT_DIR (default $TMPDIR or /tmp)
#
# The agent runs in the empty stage/ directory and can only use the tools of
# the "devcon" MCP server profile: everything it knows about Liferay comes
# from the profile instructions and the OpenAPI-generated tool schemas.

set -euo pipefail

source "$(dirname "$0")/../lib.sh"

PROMPT="$(cat "$ROOT_DIR/demo/02-prompt.txt")"

DISALLOWED_TOOLS="Agent Bash Edit Glob Grep NotebookEdit Read Skill Task WebFetch WebSearch Write"

cd "$ROOT_DIR/stage"

jq -n \
	--arg authorization "Basic $(printf '%s' "$LIFERAY_AUTH" | base64 -w0)" \
	--arg url "$LIFERAY_URL/o/mcp/devcon" \
	'{mcpServers: {liferay: {headers: {Authorization: $authorization}, type: "http", url: $url}}}' > .mcp.json

if [ "${1:-}" = "--rehearse" ]; then
	transcript_dir="${TRANSCRIPT_DIR:-${TMPDIR:-/tmp}}"

	mkdir -p "$transcript_dir"

	transcript="$transcript_dir/devcon-rehearsal-$(date +%Y%m%d-%H%M%S).jsonl"

	claude -p "$PROMPT" \
		--allowedTools mcp__liferay \
		--disallowedTools $DISALLOWED_TOOLS \
		--mcp-config .mcp.json \
		--output-format stream-json \
		--strict-mcp-config \
		--verbose > "$transcript"

	jq -r 'select(.type == "assistant") | .message.content[] | select(.type == "tool_use") | "  tool: \(.name)"' "$transcript"
	jq -r 'select(.type == "result") | "\n\(.result)\n\n  \(.duration_ms / 1000 | floor) s, \(.num_turns) turns, $\(.total_cost_usd * 100 | floor / 100)"' "$transcript"
	echo "  transcript: $transcript"
else
	exec claude "$PROMPT" \
		--allowedTools mcp__liferay \
		--disallowedTools $DISALLOWED_TOOLS \
		--mcp-config .mcp.json \
		--strict-mcp-config
fi
