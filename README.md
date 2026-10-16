# One API, Thousands of Sites: demo kit

Scripts and payloads for the Devcon 2026 session "One API, Thousands of Sites: Unleashing the Fragment Headless API".

The story: Acme Coffee runs one Liferay site per store. Every store site is connected to the design library `acme-design-library`. We build the fragments of the stores in the library through the API, let an AI agent create one more, compose the store pages with the Pages API, and change the campaign of every store with one call.

## Requirements

- A Liferay portal built from the [`devcon-2026-fragment-demo`](https://github.com/ruben-pulido/liferay-portal/tree/devcon-2026-fragment-demo) branch of `liferay-portal` (`git fetch https://github.com/ruben-pulido/liferay-portal.git devcon-2026-fragment-demo`). It is a development build with prototype endpoints: see [Portal changes](#portal-changes).
- `bash`, `curl`, `jq` and Claude Code (`claude`, signed in) for the AI step.
- Defaults: `http://localhost:8080` and `test@liferay.com:test`. Override them with `LIFERAY_URL` and `LIFERAY_AUTH`; every script, including the agent's MCP connection, uses these two variables.

## Setting up the portal

1. Build and deploy the branch. On a fresh checkout, the usual `ant all`. On a bundle already built from the same base, deploying the changed modules is enough (all in `fragment` and `headless-admin-fragment`):

	```bash
	cd liferay-portal

	for module in \
		modules/apps/fragment/fragment-api \
		modules/apps/fragment/fragment-service \
		modules/apps/headless/headless-admin-fragment/headless-admin-fragment-api \
		modules/apps/headless/headless-admin-fragment/headless-admin-fragment-client \
		modules/apps/headless/headless-admin-fragment/headless-admin-fragment-impl
	do
		(cd "$module" && "$OLDPWD/gradlew" deploy)
	done
	```

	These bundles live in `osgi/portal`, so restart the portal afterwards; a redeploy does not hot-reload them.

1. Enable the features the demo uses:
	- Append [`setup/portal/portal-ext.properties`](setup/portal/portal-ext.properties) to the bundle's `portal-ext.properties`: the Fragment Headless API (`LPD-39244`), design libraries (`LPD-57283`) and the MCP server (`LPD-63311`).
	- Copy [`setup/portal/com.liferay.mcp.server.rest.internal.configuration.MCPServerConfiguration.config`](setup/portal/com.liferay.mcp.server.rest.internal.configuration.MCPServerConfiguration.config) to the bundle's `osgi/configs`. It enables the MCP server, which is off by default even with the flag.

1. Restart the portal and wait until it answers.

## Before the show

```bash
./setup/00-setup.sh        # design library + 2 store sites connected to it
./setup/10-mcp-profile.sh  # "devcon" profile of Liferay's MCP server
./demo.sh reset            # empty library, no store pages
```

Both setup scripts are idempotent. Warm up the agent once (`./demo/02-ai-fragment.sh --rehearse`, transcript in `$TRANSCRIPT_DIR`, default `$TMPDIR` or `/tmp`) and run `./demo.sh reset` again, so the first real run is not the first run of the day.

## Step by step: `demo.sh`

To follow every request and response, one key press at a time (rehearsal, or presenting the API itself):

```bash
./demo.sh reset         # library and stores, nothing else
./demo.sh               # all steps: explains each one, shows the request, waits for a key, shows the response
./demo.sh step6         # a single step (step0 ... step7)
NO_PAUSE=1 ./demo.sh    # no key presses
AI_FALLBACK=1 ./demo.sh # step 4 uses the cached agent run instead of launching Claude Code
```

Each request prints its method, path and JSON body (long HTML, CSS and Base64 shortened). Press any key to send it. The response shows the HTTP status (green for 2xx, red otherwise), the time it took and the relevant fields.

Each step starts with "In the UI" lines: what to open and what to look for after the requests, with links to the screen (sign in first): the Design Libraries list, the library, the Acme Campaigns set and its Resources tab, the devcon MCP profile's tools, each store's Pages admin and the two store pages. The library links are built from the library's id at run time, so they keep working after `./demo.sh reset` or a fresh `setup/00-setup.sh`.

Gotchas found while preparing the links:

- If another portal build ran on the same host and port in the same browser, the browser can serve its cached JavaScript modules and the admin screens render blank, with "does not provide an export named ..." errors in the console. Hard-reload with Ctrl+Shift+R, or use a separate browser profile for the demo.
- The Design Libraries list (and `GET /asset-libraries`) is search-backed. If it shows "No Design Libraries Yet" while the library exists, reindex: Control Panel > Search > Index Actions > All Search Indexes > Reindex.

| Step | Requests |
| --- | --- |
| 0 | Who we are, the stores connected to the library, the empty library |
| 1 | `PUT` the fragment set in the design library |
| 2 | `POST` the autumn image as a resource of the set |
| 3 | `POST` the Seasonal Promo fragment (the HTML is printed first) |
| 4 | MCP `tools/list` (what the agent sees), the prompt, then Claude Code; `GET` of the fragment it created |
| 5 | `GET` each fragment from the library, `PUT` the Store Home page of each store with their content and a reference to them, then what each store renders |
| 6 | `POST` the winter image, `PUT` the winter version of the fragment, then the stores still showing autumn |
| 7 | `POST .../propagate`, then the stores showing winter |

## On stage

| Step | Command | What the audience sees |
| --- | --- | --- |
| Demo 1: build by API | `./demo/01-build-by-api.sh` | A fragment set, an image resource and the Seasonal Promo fragment created in the design library. Show them in the Design Library UI. |
| Demo 2: AI | `./demo/02-ai-fragment.sh` | Claude Code, prompt prefilled (`demo/02-prompt.txt`), creates the Store Hours fragment through Liferay's MCP server. About 35 s, 5 tool calls. |
| Demo 3: pages | `./demo/03-compose-pages.sh` | The store page of both sites, composed from the two library fragments. Refresh both browser tabs. |
| Demo 4: propagate | `./demo/04-propagate.sh` | The fragment switches to the winter campaign in the library; both stores still show autumn; press Enter; one call (under 1 s) and both stores show winter. Refresh both tabs. |
| Reset | `./demo/reset.sh` | Back to the starting point. |

Demo 3 adds the Store Hours fragment only if it exists, so a failed Demo 2 does not break the rest of the run.

### Demo 2 details

- The agent runs in the empty `stage/` directory with every built-in tool disabled: it can only call the eight tools of the `devcon` MCP profile.
- Everything it knows about Liferay comes from the profile instructions (`mcp/instructions.md`, stored in the portal by `setup/10-mcp-profile.sh`) and from the tool schemas, which Liferay generates from the OpenAPI of each headless API. The prototype `propagate` endpoint became an MCP tool without any MCP-specific code.
- If the API rejects a payload, the agent reads the error and fixes the payload. A rehearsal hit this once (`Unable to map JSON path: fragmentVersions.null.configuration`, a fragment version without `status`) and recovered on the next call. Good moment to narrate if it happens live.
- Fallback if the network or the model misbehaves: `./demo/02-fallback.sh` creates the same fragment from a cached agent run (`payloads/store-hours.json`).
- Variant for a longer slot: add "Then add it to the home page of every store, right below the seasonal promo" to the prompt. The agent composes the pages itself with `putSiteSitePage` (about 100 s, 16 turns in rehearsal).

## Files

| Path | Purpose |
| --- | --- |
| `lib.sh` | `api` (curl with errors on stderr), payload builders, `show_sites` |
| `setup/` | Pre-show setup, idempotent |
| `demo/` | One script per demo, plus `reset.sh` |
| `payloads/seasonal-promo/` | HTML, CSS and configuration of the Seasonal Promo fragment, autumn and winter |
| `assets/` | Campaign images uploaded as fragment resources |
| `mcp/instructions.md` | Instructions of the `devcon` MCP profile |
| `setup/portal/` | Feature flags and MCP server configuration for the portal |
| `stage/` | Empty working directory of the agent; `.mcp.json` (its connection to `$LIFERAY_URL/o/mcp/devcon`) is generated on each run |

## Portal changes

Branch `devcon-2026-fragment-demo` of `liferay-portal`: master as of 2026-10-03, two commits that attach resource files added through the API to their fragment set, and these changes:

- `headless-admin-fragment`: design library variants of the write operations (`POST`/`PUT` fragment sets, `GET`/`POST` fragments of a set, `GET`/`PUT` fragments, `POST` resource files of a set) and `POST .../fragments/{erc}/propagate` for design libraries and sites.
- `fragment-service`: `FragmentEntryLocalService.propagateChanges(long)` exposes the existing propagation, which already reaches every site connected to the design library. Before, it only ran on publish when "Propagate fragment changes automatically" was enabled.

## Propagation at scale

`setup/90-scale-test.sh create|measure|delete N` adds N store sites connected to the library, each with the store page, and times propagation. Measured on a development laptop (2026-10-05, 102 sites, 204 fragment instances counting each page's draft): 7.1 to 8.3 s per propagation, all instances updated. That is about 40 ms per instance, synchronous within the request: thousands of sites would take minutes, so the production version should run propagation as a background task and return immediately.
