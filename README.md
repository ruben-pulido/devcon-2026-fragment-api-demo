# One API, Thousands of Sites: demo kit

Scripts and payloads for the Devcon 2026 session "One API, Thousands of Sites: Unleashing the Fragment Headless API".

The story: Ray’s Hotels opens its first hotel, in Madrid (DevCon 2025). We build its Liferay site, its fragments and its hotel page from an empty portal, with the headless APIs alone. Then a second hotel opens in London (DevCon 2026): to launch campaigns in all hotels at the same time, the campaigns move from the Madrid site to a design library connected to both hotels, and an AI agent adds a fragment to the library. Ray’s then opens a hotel in every other city that has hosted DevCon since 2013, and a new campaign reaches all eight hotels with one propagation from the UI. Each hotel has its own Hotel Header, with Ray, Liferay's mascot, in the hotel's colors next to the city's name, and the city's skyline seen from a room, so the hotels are easy to tell apart.

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

1. Sign in and switch to dark mode with the moon button ("Switch to Dark Mode") in the Product Menu, Applications or Control Panel header. Dark mode only covers the administration UI; the hotel pages are dark by design of their fragments.

## Setting up the demo windows on another machine

There is nothing to set up by hand for the browser: the first run of `demo/browser.sh` (which `demo/windows.sh` runs) creates its profile.

- It creates a Chrome profile of its own in `~/.cache/devcon-demo-browser`, so your everyday Chrome is untouched and another portal's cached JavaScript never gets in the way.
- It writes the bookmarks (one folder per act, one bookmark per step) and makes the bookmarks bar always visible, without the apps shortcut or tab groups.
- It starts Chrome with that profile, with its remote control on localhost (`DEMO_CDP_PORT`, default 9333) so the browser can follow the demo, and with the window size and zoom of the presentation screen.
- It closes a Chrome already running on that profile first, so the bookmarks are written again and the window lands in its place.

By hand, once: sign in to the portal in that window as `test@liferay.com` (or the user of `LIFERAY_AUTH`), and switch to dark mode with the moon button in the Product Menu. The sign-in stays in the profile for the next runs; `demo/browser.sh` prints both reminders. To start from a fresh profile, delete `~/.cache/devcon-demo-browser` and run `demo/browser.sh` again (and sign in again).

What the machine needs (`demo/check.sh` checks it and says what is missing):

- Chrome or Chromium on the `PATH`, or `CHROME=/path/to/chrome`.
- Node.js 18 or later, for the browser to follow the demo. Without it, the demo runs and the bookmarks have every screen.
- `wmctrl` and `xdotool` to place the windows; without them the windows open but have to be placed by hand.
- Ptyxis for `demo/terminal.sh`, or any terminal of at least 73 × 37 with a large font.
- A Linux desktop that runs X11 applications; the scripts were made on GNOME. On macOS or Windows, start Chrome by hand with a profile of its own and `--remote-debugging-port=9333`, and import the bookmarks.

In short:

```bash
./demo/check.sh     # the portal, the tools, the starting point
./demo/windows.sh   # the terminal and the browser; the first time, sign in and switch to dark mode
./demo.sh
```

## Before the show

On the day, one command gets everything ready and says what is not, without any AI or internet:

```bash
./demo/check.sh
```

It checks the tools, the portal and its demo endpoints, runs the MCP setup script and `./demo.sh reset`, checks that the starting point is clean, starts the hotel grid, and checks what the AI agent needs. When the agent cannot run (no Claude Code, no internet), it says to run `AI_FALLBACK=1 ./demo.sh`, which uses the cached agent run.

What it runs, step by step:

```bash
./setup/10-mcp-profile.sh  # "devcon" profile of Liferay's MCP server, to rehearse the agent alone (the demo creates it in act 4, the reset removes it)
./demo.sh reset            # no hotel sites, no design library, no MCP profile
./demo/hotel-grid.py &     # the hotel grid at http://localhost:8090, for acts 3, 6 and 7
./demo/windows.sh          # both demo windows, side by side: the terminal and the browser
./demo/close.sh            # closes whatever of the demo is open: a running demo.sh, the demo terminal and browser, the hotel grid (--dry-run to only list them)
```

`demo/windows.sh` runs `demo/terminal.sh` (a Ptyxis window with the demo font on the left half of the screen, 73 × 37 at 16 points; `demo/windows.sh ./demo.sh` starts the demo in it) and `demo/browser.sh` (a Chrome window on the right half, with the sign-in; it also starts the hotel grid); each also works alone. The browser's bookmarks bar has one folder per act (0. Start, 1. Madrid, 2. London, 3. Shared campaigns, 4. MCP, 5. Agent, 6. Cities, 7. Winter), holding the screen of every step that changes the browser, named after the step's number on the terminal (act.step; a, b when a step shows several screens) and a short label. `demo/browser.sh` prints this legend too. On the terminal, a progress bar at the top shows every act's steps as dots, with the same short names above the acts that have started, so the audience sees where the demo is without learning what comes next. The design library's own screens have no fixed URL, so their bookmarks open the Design Libraries list. With `AI_FALLBACK=1`, act 5 has no "Check the agent’s calls" step, so its later steps are one number lower.

| Bookmark | Screen |
| --- | --- |
| 0.1 Sign in | Sign in |
| 1.1 Sites | Sites (Madrid appears) |
| 1.2 Hotel set | Madrid: Ray’s Hotel fragments (the set appears) |
| 1.3 View image | Madrid: Ray’s Hotel resources (madrid-room.svg) |
| 1.4 Ray image | Madrid: Ray’s Hotel resources (madrid-ray.png) |
| 1.5 Header | Madrid: Ray’s Hotel fragments (Hotel Header) |
| 1.6 Campaigns | Madrid: Ray’s Campaigns fragments |
| 1.7 Resources | Madrid: Ray’s Campaigns resources (the images folder) |
| 1.8 Images folder | Madrid: Ray’s Campaigns resources, then open the images folder |
| 1.9 Offer | Madrid: Ray’s Campaigns fragments (Seasonal Offer) |
| 1.10a Pages | Madrid: pages (before and after the request) |
| 1.10b Madrid hotel | Madrid hotel page |
| 2.1a Sites | Sites (London appears) |
| 2.1b London header | London: Ray’s Hotel fragments (London's Hotel Header) |
| 2.2 Libraries | Design Libraries (Ray’s Design Library appears) |
| 2.3 Connect Madrid | Design Libraries > Ray’s Design Library: Connected Sites (before and after) |
| 2.4 Connect London | Design Libraries > Ray’s Design Library: Connected Sites |
| 3.2 Library set | Design Libraries > Ray’s Design Library (empty), then its Ray’s Campaigns |
| 3.4 Resources | Design Libraries > Ray’s Design Library > Ray’s Campaigns > Resources |
| 3.6 Images | Design Libraries > Ray’s Design Library > Ray’s Campaigns > Resources > images |
| 3.8 Fragments | Design Libraries > Ray’s Design Library > Ray’s Campaigns fragments |
| 3.9 Madrid hotel | Madrid hotel page |
| 3.10a Pages | London: pages (before and after the request) |
| 3.10b London hotel | London hotel page |
| 3.11a Set gone | Madrid: Ray’s Hotel fragments (Ray’s Campaigns is gone) |
| 3.11b Grid | Hotel grid: Madrid and London |
| 4.1 Profile | MCP Server: profiles (devcon appears) |
| 4.2 Tools | MCP Server: the devcon profile's tools |
| 5.3 Breakfast Hours | Design Libraries > Ray’s Design Library > Ray’s Campaigns fragments (Breakfast Hours) |
| 5.4 Thumbnail | Design Libraries > Ray’s Design Library > Ray’s Campaigns: Breakfast Hours with its thumbnail, then open it |
| 5.5 Madrid | Hotel grid: Madrid alone (Breakfast Hours appears) |
| 5.6 London | Hotel grid: London alone (Breakfast Hours appears) |
| 6.1 All hotels | Hotel grid: all eight hotels (they appear as they open) |
| 7.2a Offer | Design Libraries > Ray’s Design Library > Ray’s Campaigns fragments (Seasonal Offer turns winter) |
| 7.2b Autumn | Hotel grid: all eight hotels (still autumn) |
| 7.3a Propagate | Design Libraries > Ray’s Design Library > Ray’s Campaigns: Seasonal Offer > View Site Usages > select all > Propagate |
| 7.3b Winter | Hotel grid: all eight hotels (winter) |

The two windows are laid out for the presentation screen, 1920 x 1080 like the slides (`DEMO_SCREEN`), and zoomed to fit the screen you rehearse on (`demo/layout.sh`): on a bigger or HiDPI screen the terminal font, the window sizes and the browser zoom grow together, so the terminal keeps at least 73 x 37 and the pages keep their width in CSS pixels.

The MCP setup script is idempotent. Rehearse once (`./demo.sh`, including the agent in act 5), then `./demo.sh reset`, so the first real run is not the first run of the day and Claude Code already trusts `stage/`.

## Running the demo: `demo.sh`

One API call per step, one key press at a time:

```bash
./demo.sh reset         # back to the starting point
./demo.sh               # all seven acts
./demo.sh act3          # a single act (act1 ... act7)
./demo.sh resume        # go on from where the demo stopped
./demo.sh offline         # any command plus offline: act 5 uses the cached agent run (when the agent or the network fails)
./demo.sh resume offline  # for example, going on from where it stopped
./demo.sh resume fix      # the same, after rebuilding the portal: clears what the demo created and silently runs every step done again (the agent from its cached run)
./demo.sh help          # these commands, every act's steps, and where resume would go on
./demo.sh from act5     # from the start of an act to the end
NO_PAUSE=1 ./demo.sh    # no key presses
AI_FALLBACK=1 ./demo.sh # act 5 uses the cached agent run instead of launching Claude Code
```

Every screen is built to be read from far away, at any terminal size (it needs at least 73 × 37, which `demo/windows.sh` gives it on half of a 1920 × 1080 screen, and with fewer than 40 rows it skips its blank lines):

- Each act opens on its own screen, with its title and its use case from the business side, and waits for a key before its first step. Then, at the top, the use case and the steps so far, the current one highlighted. A new step starts on a clean screen.
- Then the call: the endpoint, wrapped after a slash, and the request body, then the status, time and response. In the steps that make a point, the value that makes it is yellow. Bodies are summarized so they fit on the screen without wrapping: long values are cut, and a page shows only the fragments it references.
- Ctrl+C while the agent runs in act 5 (to leave Claude Code) only stops the agent: the demo goes on, and one more stray Ctrl+C at the next key press is ignored too. If the demo stops anyway, `./demo.sh resume` goes on from the first step not done yet, even in the middle of an act: it runs through the steps done already without showing them or calling the portal (it keeps every step's response in `~/.cache/devcon-demo-state`), so the screen and the progress bar are where they were. A step that had sent its request counts as done; one that had not is shown again. `./demo.sh reset` forgets it all.
- At any key prompt, ← and → browse the screens shown so far, exactly as they were, without calling anything again; any other key goes back to the current screen. A presentation clicker works too: Page Down (next) goes on, Page Up (back) goes back.
- The browser follows the demo: each step shows its screen in the demo browser and reloads it after the request, so what the request created appears. `demo/browser.sh` starts Chrome with its remote control on localhost (`DEMO_CDP_PORT`, default 9333), and `demo/browser-driver.mjs` (Node.js) drives the tab on display. The design library's screens need its id, which `demo.sh` looks up. After the Madrid Hotel Header is created (1.5), the browser opens it in the fragment editor. When a step has two screens (the a and b bookmarks), the second follows two seconds after the first one's reload: the Madrid hotel page after the list of pages that now has it, for example. Each change comes a second after the terminal's (`DEMO_BROWSER_DELAY`, in seconds), so the audience can follow both. On the fragments and design library screens, it closes Liferay's side menu if it is open, so their content gets the whole width. Steps that upload into or read the `images` folder open that folder (the Fragment API does not give a folder's id, so the browser opens it by name from the Resources tab), and the reload after the upload shows the new file. `DEMO_BROWSER=0 ./demo.sh` leaves the browser alone; the bookmarks still have every screen.
- What to show in the browser at each step is in the `# UI:` comments of `demo.sh`.

| Act | Use case | Steps |
| --- | --- | --- |
| 1. Madrid opens | Ray’s Hotels opens its first hotel, from an empty portal | Create the Madrid site, its Ray’s Hotel fragment set, the view from a room, Ray in Madrid's colors and the Hotel Header (with a thumbnail), then the Ray’s Campaigns fragment set, its `images` resource folder, the autumn image, the Seasonal Offer fragment (with a thumbnail), and Madrid's hotel page |
| 2. London opens | A second hotel; campaigns must launch in all hotels at the same time | Open the London site with the same calls as Madrid (site, fragment set, view and Ray images, Hotel Header), one line on the screen; create the design library and connect both sites to it |
| 3. Share the campaigns | Move the campaigns from Madrid to the design library: copy, repoint, delete | Read and create the fragment set, its folders, files and fragments (with their thumbnails) in the library, point Madrid's page to the library's offer, create London's page, delete Madrid's set |
| 4. The agent’s toolbox | Before an AI agent can help, it needs a profile on Liferay’s MCP server: a briefing and the only tools it may use | Create the `devcon` profile with its instructions, give it seven tools from three headless APIs, activate it, list what the agent sees |
| 5. An AI agent builds the next fragment | Claude Code, with only its MCP profile's tools, creates Breakfast Hours | Run the agent, list the calls it made, read its fragment, give it a thumbnail (a headless Chrome screenshot of its HTML and CSS), add it to both hotel pages |
| 6. A hotel in every DevCon city | Ray opens hotels in Berlin (2013), Darmstadt (2014), Amsterdam (2017), Mainz (2019), Porto (2023) and Budapest (2024) | The same calls as for London, one line per city on the screen, then list the design library's eight connected sites |
| 7. Winter campaign | One change in the library reaches all eight hotels | Upload the winter image, update the Seasonal Offer, propagate from the UI (Seasonal Offer > ⋮ > View Site Usages, select all, Propagate): with the browser following the demo, one key press makes the browser do those clicks at a pace the audience can follow, then shows the hotel grid; without it, do them by hand |

Act 4 adds Breakfast Hours to the pages only if it exists, so a failed agent run does not break the rest of the demo.

### The hotel grid

`demo/hotel-grid.py` serves every hotel page in a 2 × 4 grid at http://localhost:8090 (`GRID_PORT`). Start it before the show and keep it open in a browser window for acts 5 and 6: a tile appears as soon as its hotel page exists, and reloads when the page changes, so the grid fills while the hotels open and turns to winter after the propagation. `?cities=Madrid,London` shows only those hotels, one under the other, each page whole. It proxies the portal so the hotel pages can be framed (Liferay sends `X-Frame-Options: SAMEORIGIN`).

Gotchas:

- If another portal build ran on the same host and port in the same browser, the browser can serve its cached JavaScript modules and the admin screens render blank or menus do not open. Hard-reload with Ctrl+Shift+R, or use a separate browser profile for the demo.
- The Design Libraries list (and `GET /asset-libraries`) is search-backed. If it shows "No Design Libraries Yet" while the library exists, reindex: Control Panel > Search > Index Actions > All Search Indexes > Reindex.
- Claude Code asks whether to trust the `stage/` folder the first time it starts there. Rehearse act 5 once on the presentation machine so the question does not come up on stage.

### The AI step

- The agent runs in the empty `stage/` directory with every built-in tool disabled: it can only call the seven tools of the `devcon` MCP profile.
- Everything it knows about Liferay comes from the profile instructions (`mcp/instructions.md`, stored in the portal when act 4 creates the profile) and from the tool schemas, which Liferay generates from the OpenAPI of each headless API. The prototype design library endpoints became MCP tools without any MCP-specific code.
- If the API rejects a payload, the agent reads the error and fixes the payload. Good moment to narrate if it happens live.
- Fallback if the network or the model misbehaves: `AI_FALLBACK=1`, or `./demo/02-fallback.sh`, creates the same kind of fragment from a cached payload (`payloads/breakfast-hours.json`).
- Variant for a longer slot: add "Then add it to the home page of every hotel, right below the Seasonal Offer" to `demo/02-prompt.txt`. The agent then composes the pages itself with `putSiteSitePage`.

## Files

| Path | Purpose |
| --- | --- |
| `demo.sh` | The demo, step by step |
| `lib.sh` | `api` (curl with errors on stderr), payload builders, `show_sites` |
| `setup/` | The MCP profile, to rehearse the agent alone, and the portal configuration |
| `setup/portal/` | Feature flags and MCP server configuration for the portal |
| `demo/` | The agent runner (`02-ai-fragment.sh`), its prompt and its fallback, and the hotel grid (`hotel-grid.py`) |
| `payloads/seasonal-offer/` | HTML, CSS and configuration of the Seasonal Offer fragment, autumn and winter |
| `payloads/hotel-header/` | The Hotel Header template (city, image, accent color) |
| `payloads/breakfast-hours/`, `payloads/breakfast-hours.json` | The cached Breakfast Hours fragment for the AI fallback |
| `assets/` | Campaign images and each hotel's header image (Ray in front of the city's skyline), uploaded as fragment resources |
| `assets/skylines/` | The city skylines the header images are drawn on |
| `assets/thumbnails/` | The fragments' thumbnails, shown in the fragments admin |
| `mcp/instructions.md` | Instructions of the `devcon` MCP profile |
| `stage/` | Empty working directory of the agent; `.mcp.json` (its connection to `$LIFERAY_URL/o/mcp/devcon`) is generated on each run |

## Portal changes

Branch `devcon-2026-fragment-demo-v2` of `liferay-portal`, on master as of 2026-10-02: design library variants of the fragment write operations in `headless-admin-fragment` (`POST`/`PUT` fragment sets, `GET`/`POST` fragments of a set, `GET`/`PUT` fragments, `POST` resource folders and resource files of a set). They reuse the site endpoints' code.

An earlier version of the demo propagated through the API; those endpoints are kept in the draft PR [ruben-pulido/liferay-portal#640](https://github.com/ruben-pulido/liferay-portal/pull/640), with a measurement at scale (102 sites: 7 to 8 s per propagation, synchronous).
