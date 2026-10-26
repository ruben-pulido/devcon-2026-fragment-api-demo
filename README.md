# One API, Thousands of Sites: demo kit

Scripts and payloads for the Devcon 2026 session "One API, Thousands of Sites: Unleashing the Fragment Headless API".

The story: Ray’s Coffee has one store, in Madrid (DevCon 2025), with its own Liferay site. We build its fragments and its store page with the headless APIs alone. Then a second store opens in London (DevCon 2026): to launch campaigns in all stores at the same time, the campaigns move from the Madrid site to a design library connected to both stores, and an AI agent adds a fragment to the library. Ray’s then opens a store in every other city that has hosted DevCon since 2013, and a new campaign reaches all eight stores with one propagation from the UI. Each store has its own Store Header, with Ray, Liferay's mascot, in front of the city's skyline, so the stores are easy to tell apart.

## Requirements

- A Liferay portal built from the [`devcon-2026-fragment-demo-v2`](https://github.com/ruben-pulido/liferay-portal/tree/devcon-2026-fragment-demo-v2) branch of `liferay-portal` (`git fetch https://github.com/ruben-pulido/liferay-portal.git devcon-2026-fragment-demo-v2`). It is a development build with prototype endpoints: see [Portal changes](#portal-changes).
- `bash`, `curl`, `jq` and Claude Code (`claude`, signed in) for the AI step.
- Chrome or Chromium (`CHROME`, found on the `PATH` by default) to give the agent's fragment a thumbnail; without it, that step is skipped.
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

On the day, one command gets everything ready and says what is not, without any AI or internet:

```bash
./demo/check.sh
```

It checks the tools, the portal and its demo endpoints, runs the setup scripts and `./demo.sh reset`, checks that the starting point is clean, starts the store grid, and checks what the AI agent needs. When the agent cannot run (no Claude Code, no internet), it says to run `AI_FALLBACK=1 ./demo.sh`, which uses the cached agent run.

What it runs, step by step:

```bash
./setup/00-setup.sh        # the Madrid site with its own Store Header fragment
./setup/10-mcp-profile.sh  # "devcon" profile of Liferay's MCP server, to rehearse the agent alone (the demo creates it in act 4, the reset removes it)
./demo.sh reset            # Madrid only: no campaigns, no store page, no other stores, no design library
./demo/store-grid.py &     # the store grid at http://localhost:8090, for acts 3, 6 and 7
./demo/windows.sh          # both demo windows, side by side: the terminal and the browser
```

`demo/windows.sh` runs `demo/terminal.sh` (a Ptyxis window with the demo font on the left half of the screen, 73 × 37 at 16 points; `demo/windows.sh ./demo.sh` starts the demo in it) and `demo/browser.sh` (a Chrome window on the right half, with the sign-in and both store grid views); each also works alone. The browser's bookmarks bar has one folder per act (0. Start, 1. Madrid, 2. London, 3. Move, 4. MCP, 5. Agent, 6. Cities, 7. Winter), holding the screen of every step that changes the browser, named after the step's number on the terminal (act.step; a, b when a step shows several screens; 1.0 is the starting point) and a short label. `demo/browser.sh` prints this legend too. The design library's own screens have no fixed URL, so their bookmarks open the Design Libraries list. With `AI_FALLBACK=1`, act 5 has no "Check the agent’s calls" step, so its later steps are one number lower.

| Bookmark | Screen |
| --- | --- |
| 0.1 Sign in | Sign in |
| 1.0 Store fragments | Madrid: Ray’s Store fragments (only the Store Header) |
| 1.1 Campaigns | Madrid: Ray’s Campaigns fragments |
| 1.2 Resources | Madrid: Ray’s Campaigns resources (the images folder) |
| 1.3 Images folder | Madrid: Ray’s Campaigns resources, then open the images folder |
| 1.4 Promo | Madrid: Ray’s Campaigns fragments (Seasonal Promo) |
| 1.5a Pages | Madrid: pages (before and after the request) |
| 1.5b Madrid store | Madrid store page |
| 2.1 Sites | Sites (London appears) |
| 2.2 London header | London: Ray’s Store fragments (London's Store Header) |
| 2.3 Libraries | Design Libraries (Ray’s Design Library appears) |
| 2.4 Connect Madrid | Design Libraries > Ray’s Design Library: Connected Sites (before and after) |
| 2.5 Connect London | Design Libraries > Ray’s Design Library: Connected Sites |
| 3.2 Library set | Design Libraries > Ray’s Design Library (empty), then its Ray’s Campaigns |
| 3.4 Resources | Design Libraries > Ray’s Design Library > Ray’s Campaigns > Resources |
| 3.6 Images | Design Libraries > Ray’s Design Library > Ray’s Campaigns > Resources > images |
| 3.8 Fragments | Design Libraries > Ray’s Design Library > Ray’s Campaigns fragments |
| 3.9 Madrid store | Madrid store page |
| 3.10 Grid | Store grid: Madrid and London |
| 3.11a Set gone | Madrid: Ray’s Store fragments (Ray’s Campaigns is gone) |
| 3.11b Grid | Store grid: Madrid and London |
| 4.1 Profile | MCP Server: profiles (devcon appears) |
| 4.2 Tools | MCP Server: the devcon profile's tools |
| 5.3 Store Hours | Design Libraries > Ray’s Design Library > Ray’s Campaigns fragments (Store Hours) |
| 5.4 Thumbnail | Design Libraries > Ray’s Design Library > Ray’s Campaigns: Store Hours with its thumbnail, then open it |
| 5.6 Grid | Store grid: Madrid and London (with Store Hours) |
| 6.1 All stores | Store grid: all eight stores (they appear as they open) |
| 7.2 Autumn | Store grid: all eight stores (still autumn) |
| 7.3a Propagate | Design Libraries > Ray’s Design Library > Ray’s Campaigns: Seasonal Promo > View Site Usages > select all > Propagate |
| 7.3b Winter | Store grid: all eight stores (winter) |

The two windows are laid out for the presentation screen, 1920 x 1080 like the slides, whatever screen you rehearse on (`DEMO_SCREEN`, `DEMO_FONT_SIZE` for another one).

Both setup scripts are idempotent. Rehearse once (`./demo.sh`, including the agent in act 5), then `./demo.sh reset`, so the first real run is not the first run of the day and Claude Code already trusts `stage/`.

## Running the demo: `demo.sh`

One API call per step, one key press at a time:

```bash
./demo.sh reset         # back to the starting point
./demo.sh               # all seven acts
./demo.sh act3          # a single act (act1 ... act7)
NO_PAUSE=1 ./demo.sh    # no key presses
AI_FALLBACK=1 ./demo.sh # act 5 uses the cached agent run instead of launching Claude Code
```

Every screen is built to be read from far away, at any terminal size (it needs at least 73 × 37, which `demo/windows.sh` gives it on half of a 1920 × 1080 screen, and with fewer than 40 rows it skips its blank lines):

- At the top, the act's use case, from the business side, and its steps so far, the current one highlighted. A new step starts on a clean screen.
- Then the call: the endpoint, wrapped after a slash, and the request body, then the status, time and response. Bodies are summarized so they fit on the screen without wrapping: long values are cut, and a page shows only the fragments it references.
- What to show in the browser at each step is in the `# UI:` comments of `demo.sh`.

| Act | Use case | Steps |
| --- | --- | --- |
| 1. Madrid opens | Ray’s Coffee opens its first store; its site exists with its Store Header | Create the Ray’s Campaigns fragment set, its `images` resource folder, the autumn image, the Seasonal Promo fragment (with a thumbnail), and Madrid's store page |
| 2. London opens | A second store with its own site and header; campaigns must launch in all stores at the same time | Create the London site and its Store Header, the design library, and connect both sites to it |
| 3. Share the campaigns | Move the campaigns from Madrid to the design library: copy, repoint, delete | Read and create the fragment set, its folders, files and fragments (with their thumbnails) in the library, point Madrid's page to the library's promo, create London's page, delete Madrid's set |
| 4. The agent’s toolbox | Before an AI agent can help, it needs a profile on Liferay’s MCP server: a briefing and the only tools it may use | Create the `devcon` profile with its instructions, give it seven tools from three headless APIs, activate it, list what the agent sees |
| 5. An AI agent builds the next fragment | Claude Code, with only its MCP profile's tools, creates Store Hours | Run the agent, list the calls it made, read its fragment, give it a thumbnail (a headless Chrome screenshot of its HTML and CSS), add it to both store pages |
| 6. A store in every DevCon city | Ray’s opens stores in Berlin (2013), Darmstadt (2014), Amsterdam (2017), Mainz (2019), Porto (2023) and Budapest (2024) | The same calls as for London, one line per city on the screen, then list the design library's eight connected sites |
| 7. Winter campaign | One change in the library reaches all eight stores | Upload the winter image, update the Seasonal Promo, propagate from the UI (Seasonal Promo > ⋮ > View Site Usages, select all, Propagate) |

Act 4 adds Store Hours to the pages only if it exists, so a failed agent run does not break the rest of the demo.

### The store grid

`demo/store-grid.py` serves every store page in a 2 × 4 grid at http://localhost:8090 (`GRID_PORT`). Start it before the show and keep it open in a browser window for acts 5 and 6: a tile appears as soon as its store page exists, and reloads when the page changes, so the grid fills while the stores open and turns to winter after the propagation. `?cities=Madrid,London` shows only those stores, one under the other, each page whole. It proxies the portal so the store pages can be framed (Liferay sends `X-Frame-Options: SAMEORIGIN`).

Gotchas:

- If another portal build ran on the same host and port in the same browser, the browser can serve its cached JavaScript modules and the admin screens render blank or menus do not open. Hard-reload with Ctrl+Shift+R, or use a separate browser profile for the demo.
- The Design Libraries list (and `GET /asset-libraries`) is search-backed. If it shows "No Design Libraries Yet" while the library exists, reindex: Control Panel > Search > Index Actions > All Search Indexes > Reindex.
- Claude Code asks whether to trust the `stage/` folder the first time it starts there. Rehearse act 5 once on the presentation machine so the question does not come up on stage.

### The AI step

- The agent runs in the empty `stage/` directory with every built-in tool disabled: it can only call the seven tools of the `devcon` MCP profile.
- Everything it knows about Liferay comes from the profile instructions (`mcp/instructions.md`, stored in the portal when act 4 creates the profile) and from the tool schemas, which Liferay generates from the OpenAPI of each headless API. The prototype design library endpoints became MCP tools without any MCP-specific code.
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
| `demo/` | The agent runner (`02-ai-fragment.sh`), its prompt and its fallback, and the store grid (`store-grid.py`) |
| `payloads/seasonal-promo/` | HTML, CSS and configuration of the Seasonal Promo fragment, autumn and winter |
| `payloads/store-header/` | The Store Header template (city, image, accent color) |
| `payloads/store-hours/`, `payloads/store-hours.json` | The cached Store Hours fragment for the AI fallback |
| `assets/` | Campaign images and each store's header image (Ray in front of the city's skyline), uploaded as fragment resources |
| `assets/skylines/` | The city skylines the header images are drawn on |
| `assets/thumbnails/` | The fragments' thumbnails, shown in the fragments admin |
| `mcp/instructions.md` | Instructions of the `devcon` MCP profile |
| `stage/` | Empty working directory of the agent; `.mcp.json` (its connection to `$LIFERAY_URL/o/mcp/devcon`) is generated on each run |

## Portal changes

Branch `devcon-2026-fragment-demo-v2` of `liferay-portal`, on master as of 2026-10-02: design library variants of the fragment write operations in `headless-admin-fragment` (`POST`/`PUT` fragment sets, `GET`/`POST` fragments of a set, `GET`/`PUT` fragments, `POST` resource folders and resource files of a set). They reuse the site endpoints' code.

An earlier version of the demo propagated through the API; those endpoints are kept in the draft PR [ruben-pulido/liferay-portal#640](https://github.com/ruben-pulido/liferay-portal/pull/640), with a measurement at scale (102 sites: 7 to 8 s per propagation, synchronous).
