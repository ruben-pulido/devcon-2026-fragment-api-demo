#!/usr/bin/env bash
#
# Gets everything ready for the demo, and says what is not: the tools, the
# portal and its demo endpoints, the MCP profile, the starting point (it runs
# the MCP setup script and ./demo.sh reset), the hotel grid, and what the AI
# agent needs. It needs no AI and no internet itself.
#
#   demo/check.sh
#
# ✓ ready, ! works but needs attention, ✗ must be fixed before the demo.
# LIFERAY_HOME is the portal's bundle directory (default
# ~/projects/liferay/p11/bundles), to say how to start it when it is down.
# Exits with 1 when something must be fixed.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

source "$ROOT_DIR/lib.sh"

GRID_URL="http://localhost:${GRID_PORT:-8090}"

failures=0
warnings=0

ok() {
	printf ' \033[32m✓\033[0m %s\n' "$1"
}

warn() {
	printf ' \033[33m!\033[0m %s\n' "$1"
	[ -n "${2:-}" ] && printf '     %s\n' "$2"
	warnings=$((warnings + 1))
}

fail() {
	printf ' \033[31m✗\033[0m %s\n' "$1"
	[ -n "${2:-}" ] && printf '     %s\n' "$2"
	failures=$((failures + 1))
}

section() {
	printf '\n\033[1m%s\033[0m\n' "$1"
}

section "Tools"

for tool in bash curl jq python3; do
	if command -v "$tool" > /dev/null; then
		ok "$tool"
	else
		fail "$tool is missing" "The demo cannot run without it."
	fi
done

command -v ptyxis > /dev/null && ok "Ptyxis (demo/terminal.sh)" || warn "Ptyxis is missing" "Use any terminal at 73 x 37 or more, with a large font."
[ -n "$CHROME" ] && ok "Chrome ($CHROME)" || warn "Chrome is missing" "Use any browser at 1000 CSS pixels wide or more."
command -v wmctrl > /dev/null && command -v xdotool > /dev/null && ok "wmctrl and xdotool (window placement)" || warn "wmctrl or xdotool is missing" "demo/windows.sh opens the windows but cannot place them."

section "Portal ($LIFERAY_URL)"

status=$(curl -s -o /dev/null -w '%{http_code}' -u "$LIFERAY_AUTH" "$LIFERAY_URL/o/headless-admin-user/v1.0/my-user-account")

if [ "$status" = 200 ]; then
	ok "It answers, and ${LIFERAY_AUTH%%:*} can sign in"
else
	tomcat=$(ls -d "${LIFERAY_HOME:-$HOME/projects/liferay/p11/bundles}"/tomcat-* 2> /dev/null | tail -1)

	if [ -n "$tomcat" ]; then
		fail "It does not answer as ${LIFERAY_AUTH%%:*} (HTTP $status)" "Start it in the background, wait about a minute, then run this again:"
		printf '\n       %s/bin/catalina.sh start\n\n' "$tomcat"
	else
		fail "It does not answer as ${LIFERAY_AUTH%%:*} (HTTP $status)" "Start the portal (LIFERAY_HOME is its bundle directory, default ~/projects/liferay/p11/bundles), or check LIFERAY_URL and LIFERAY_AUTH."
	fi

	printf '\n\033[1;31mThe portal is not ready: nothing else can be checked.\033[0m\n'

	exit 1
fi

paths=$(curl -s -u "$LIFERAY_AUTH" "$LIFERAY_URL/o/headless-admin-fragment/v1.0/openapi.json" | jq -r '.paths | keys[]' 2> /dev/null)

if grep -q 'design-libraries/{designLibraryExternalReferenceCode}/fragment-sets/{fragmentSetExternalReferenceCode}/resource-folders' <<< "$paths"; then
	ok "The demo's design library endpoints are deployed"
else
	fail "The design library endpoints are missing" "The portal must be built from the devcon-2026-fragment-demo-v2 branch (see the README), with the Fragment Headless API and design library feature flags on."
fi

section "MCP server"

if ./setup/10-mcp-profile.sh > /dev/null 2>&1; then
	tools=$(curl -s -u "$LIFERAY_AUTH" -X POST -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
		-d '{"id": 1, "jsonrpc": "2.0", "method": "tools/list"}' "$LIFERAY_URL/o/mcp/devcon" | jq -r '.result.tools | length' 2> /dev/null)

	if [ "${tools:-0}" = 7 ]; then
		ok "It works: a trial devcon profile gave the agent its 7 tools (the reset below removes it; act 4 creates it on stage)"
	else
		fail "A trial devcon profile gave the agent ${tools:-no} tools instead of 7" "Check the MCP server's feature flag and configuration (setup/portal)."
	fi
else
	fail "setup/10-mcp-profile.sh failed" "Run it by hand to see why."
fi

section "Starting point"

# leftovers: the demo data that is not part of the starting point, one item
# per line as DESCRIPTION|COMMAND THAT DELETES IT.
leftovers() {
	local city name site

	for city in "${DEVCON_CITIES[@]}"; do
		IFS='|' read -r _ site name _ _ <<< "$city"

		if api GET "$SITE_API/sites/$site/site-pages/hotel-home" > /dev/null 2>&1; then
			echo "$name's hotel page|curl -u '$LIFERAY_AUTH' -X DELETE $SITE_API/sites/$site/site-pages/hotel-home"
		fi

		if site_exists "$site"; then
			echo "the $name site|curl -u '$LIFERAY_AUTH' -X DELETE $SITE_API/sites/$site"
		fi
	done

	if library_exists; then
		echo "the design library|curl -u '$LIFERAY_AUTH' -X DELETE $LIFERAY_URL/o/headless-asset-library/v1.0/asset-libraries/$DESIGN_LIBRARY_ERC"
	fi
}

before=$(leftovers)

./demo.sh reset > /dev/null 2>&1

after=$(leftovers)

cleaned=$(comm -23 <(sort <<< "$before") <(sort <<< "$after") | grep -v '^$')

if [ -n "$cleaned" ]; then
	ok "Cleaned up a previous run: $(cut -d'|' -f1 <<< "$cleaned" | paste -sd, - | sed 's/,/, /g')"
fi

if [ -z "$after" ]; then
	ok "Starting point: no hotel sites, no design library, no MCP profile"
else
	fail "./demo.sh reset could not remove all of a previous run. Delete these, then run this again:"

	while IFS='|' read -r description command; do
		printf '     %s:\n       %s\n' "$description" "$command"
	done <<< "$after"
fi

section "Hotel grid ($GRID_URL)"

if ! curl -s -o /dev/null "$GRID_URL/"; then
	setsid "$ROOT_DIR/demo/hotel-grid.py" > "$HOME/.cache/devcon-hotel-grid.log" 2>&1 &

	for _ in $(seq 1 20); do
		curl -s -o /dev/null "$GRID_URL/" && break

		sleep 0.5
	done
fi

if curl -s "$GRID_URL/" | grep -q 'class="tile"'; then
	ok "It is running"
else
	fail "It does not start" "Run ./demo/hotel-grid.py by hand to see why."
fi

section "The AI agent (act 5)"

if command -v claude > /dev/null || [ -x "$HOME/.local/bin/claude" ]; then
	ok "Claude Code is installed"
else
	warn "Claude Code is missing" "Run the demo with AI_FALLBACK=1 ./demo.sh: act 5 then uses the cached agent run."
fi

trusted=$(jq -r --arg dir "$ROOT_DIR" '[.projects // {} | to_entries[] | select(.value.hasTrustDialogAccepted == true) | .key | select(. as $key | $dir | startswith($key))] | length' "$HOME/.claude.json" 2> /dev/null)

if [ "${trusted:-0}" -gt 0 ]; then
	ok "Claude Code trusts the demo kit's folder (no trust question on stage)"
else
	warn "Claude Code has not been told to trust this folder" "Run 'claude' once in stage/ and answer the question, or it will ask during act 5."
fi

if curl -s -o /dev/null --max-time 5 https://api.anthropic.com; then
	ok "The internet answers (the agent needs it)"
else
	warn "No internet: the agent cannot run" "Run the demo with AI_FALLBACK=1 ./demo.sh: act 5 then uses the cached agent run."
fi

if [ -s "$ROOT_DIR/payloads/breakfast-hours.json" ]; then
	ok "The cached agent run is there (payloads/breakfast-hours.json)"
else
	fail "payloads/breakfast-hours.json is missing" "AI_FALLBACK=1 needs it."
fi

printf '\n'

if [ $failures -gt 0 ]; then
	printf '\033[1;31m%d thing(s) to fix before the demo.\033[0m\n' "$failures"

	exit 1
fi

if [ $warnings -gt 0 ]; then
	printf '\033[1;33mReady, with %d warning(s) above.\033[0m\n' "$warnings"
else
	printf '\033[1;32mReady: open the windows (./demo/windows.sh) and run ./demo.sh.\033[0m\n'
fi

printf 'In the browser: sign in as %s and switch to dark mode (moon button in the Product Menu).\n' "${LIFERAY_AUTH%%:*}"
