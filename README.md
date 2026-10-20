# One API, Thousands of Sites: demo kit

Scripts and payloads for the Devcon 2026 session "One API, Thousands of Sites: Unleashing the Fragment Headless API".

The story: Ray’s Coffee has one store, in Madrid, with its own Liferay site. We build its fragments and its store page with the headless APIs alone. Then a second store opens in London: the shared campaigns move from the Madrid site to a design library connected to both stores, an AI agent adds a fragment to the library, and a new campaign reaches every store with one propagation from the UI. Each store keeps its own Store Header (city name and skyline), so Madrid and London are easy to tell apart.

## Requirements

- A Liferay portal built from the [`devcon-2026-fragment-demo-v2`](https://github.com/ruben-pulido/liferay-portal/tree/devcon-2026-fragment-demo-v2) branch of `liferay-portal` (`git fetch https://github.com/ruben-pulido/liferay-portal.git devcon-2026-fragment-demo-v2`). It is a development build with prototype endpoints: see [Portal changes](#portal-changes).
- `bash`, `curl`, `jq` and Claude Code (`claude`, signed in) for the AI step.
- Defaults: `http://localhost:8080` and `test@liferay.com:test`. Override them with `LIFERAY_URL` and `LIFERAY_AUTH`; every script, including the agent's MCP connection, uses these two variables.

## Setting up the portal

1. Build and deploy the branch. On a fresh checkout, the usual `ant all`. On a bundle already built from the same base, deploying the changed modules is enough:

	```bash
	cd liferay-portal

	for module in \
		modules/apps/headless/headless-admin-fragment/headless-admin-fragment-api \
		modules/apps/headless/headless-admin-fragment/headless-admin-fragment-client \
		modules/apps/headless/headless-admin-fragment/headless-admin-fragment-impl
	do
		(cd "$module" && "$OLDPWD/gradlew" deploy)
	done
	```

	A running portal picks the redeployed bundles up without a restart.

1. Enable the features the demo uses:
	- Append [`setup/portal/portal-ext.properties`](setup/portal/portal-ext.properties) to the bundle's `portal-ext.properties`: the Fragment Headless API (`LPD-39244`), design libraries (`LPD-57283`), the MCP server (`LPD-63311`) and dark mode (`LPD-57922`).
	- Copy [`setup/portal/com.liferay.mcp.server.rest.internal.configuration.MCPServerConfiguration.config`](setup/portal/com.liferay.mcp.server.rest.internal.configuration.MCPServerConfiguration.config) to the bundle's `osgi/configs`. It enables the MCP server, which is off by default even with the flag.

1. Restart the portal and wait until it answers.

1. Sign in and switch to dark mode with the moon button ("Switch to Dark Mode") in the Product Menu, Applications or Control Panel header. Dark mode only covers the administration UI; the store pages are dark by design of their fragments.

## Before the show

```bash
./setup/00-setup.sh        # the Madrid site with its own Store Header fragment
./setup/10-mcp-profile.sh  # "devcon" profile of Liferay's MCP server
./demo.sh reset            # Madrid only: no shared fragments, no store page, no London, no design library
```

Both setup scripts are idempotent. Warm up the agent once (`./demo/02-ai-fragment.sh --rehearse` needs the design library, so run it after step 6 of a rehearsal), then `./demo.sh reset`, so the first real run is not the first run of the day.

## Running the demo: `demo.sh`

Every request and response, one key press at a time:

```bash
./demo.sh reset         # back to the starting point
./demo.sh               # all steps: explains each one, shows the request, waits for a key, shows the response
./demo.sh step6         # a single step (step0 ... step9)
NO_PAUSE=1 ./demo.sh    # no key presses
AI_FALLBACK=1 ./demo.sh # step 7 uses the cached agent run instead of launching Claude Code
```

Each request prints its method, path and JSON body (long HTML, CSS and Base64 shortened). Press any key to send it. The response shows the HTTP status (green for 2xx, red otherwise), the time it took and the relevant fields.

Each step starts with "In the UI" lines: what to open and what to look for after the requests, with links to the screen (sign in first).

| Step | What happens |
| --- | --- |
| 0 | The starting point: Madrid with its own Store Header, no shared fragments, no store page |
| 1 | `PUT` the Ray’s Campaigns fragment set in the Madrid site |
| 2 | `POST` the autumn image as a resource of the set |
| 3 | `POST` the Seasonal Promo fragment (the HTML is printed first) |
| 4 | `GET` the fragments, `PUT` Madrid's store page with the Pages API: its header and the promo |
| 5 | London opens: `PUT` the London site, its own set, skyline and Store Header; `PUT` the design library; `PUT` each store's connection to it |
| 6 | Move the campaigns: copy the set, its images (read with `nestedFields=fileURLReference.fileBase64`) and its fragments into the library, `PUT` both store pages to reference the library's promo, `DELETE` Madrid's set |
| 7 | MCP `tools/list` (what the agent sees), the prompt, then Claude Code creates Store Hours in the library; both store pages get it |
| 8 | `POST` the winter image, `PUT` the winter version of the promo in the library, then the stores still showing autumn |
| 9 | In the UI: Seasonal Promo > ⋮ > View Site Usages, select Madrid and London, Propagate; then the stores showing winter |

Step 7 adds Store Hours to the pages only if it exists, so a failed agent run does not break the rest of the demo.

Gotchas:

- If another portal build ran on the same host and port in the same browser, the browser can serve its cached JavaScript modules and the admin screens render blank, with "does not provide an export named ..." errors in the console. Hard-reload with Ctrl+Shift+R, or use a separate browser profile for the demo.
- The Design Libraries list (and `GET /asset-libraries`) is search-backed. If it shows "No Design Libraries Yet" while the library exists, reindex: Control Panel > Search > Index Actions > All Search Indexes > Reindex.

### The AI step

- The agent runs in the empty `stage/` directory with every built-in tool disabled: it can only call the seven tools of the `devcon` MCP profile.
- Everything it knows about Liferay comes from the profile instructions (`mcp/instructions.md`, stored in the portal by `setup/10-mcp-profile.sh`) and from the tool schemas, which Liferay generates from the OpenAPI of each headless API. The prototype design library endpoints became MCP tools without any MCP-specific code.
- If the API rejects a payload, the agent reads the error and fixes the payload. Good moment to narrate if it happens live.
- Fallback if the network or the model misbehaves: `AI_FALLBACK=1`, or `./demo/02-fallback.sh`, creates the same kind of fragment from a cached payload (`payloads/store-hours.json`).
- Variant for a longer slot: add "Then add it to the home page of every store, right below the seasonal promo" to `demo/02-prompt.txt`. The agent then composes the pages itself with `putSiteSitePage`.

## Files

| Path | Purpose |
| --- | --- |
| `demo.sh` | The demo, step by step |
| `lib.sh` | `api` (curl with errors on stderr), payload builders, `show_sites` |
| `setup/` | Pre-show setup, idempotent |
| `setup/portal/` | Feature flags and MCP server configuration for the portal |
| `demo/` | The agent runner (`02-ai-fragment.sh`), its prompt and its fallback |
| `payloads/seasonal-promo/` | HTML, CSS and configuration of the Seasonal Promo fragment, autumn and winter |
| `payloads/store-header/` | The Store Header template (city, skyline, accent color) |
| `payloads/store-hours/`, `payloads/store-hours.json` | The cached Store Hours fragment for the AI fallback |
| `assets/` | Campaign images and the Madrid and London skylines, uploaded as fragment resources |
| `mcp/instructions.md` | Instructions of the `devcon` MCP profile |
| `stage/` | Empty working directory of the agent; `.mcp.json` (its connection to `$LIFERAY_URL/o/mcp/devcon`) is generated on each run |

## Portal changes

Branch `devcon-2026-fragment-demo-v2` of `liferay-portal`, on master as of 2026-10-02: design library variants of the fragment write operations in `headless-admin-fragment` (`POST`/`PUT` fragment sets, `GET`/`POST` fragments of a set, `GET`/`PUT` fragments, `POST` resource files of a set). They reuse the site endpoints' code.

An earlier version of the demo propagated through the API; those endpoints are kept in the draft PR [ruben-pulido/liferay-portal#640](https://github.com/ruben-pulido/liferay-portal/pull/640), with a measurement at scale (102 sites: 7 to 8 s per propagation, synchronous).
