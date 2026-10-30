// Moves the demo browser (demo/browser.sh) along with demo.sh, through
// Chrome's DevTools protocol on DEMO_CDP_PORT (default 9333). It reads one
// command per line on its standard input:
//
//   goto URL   show URL in the tab on display
//   reload     reload the tab on display
//   wait N     wait N more seconds before the next command
//   sync       answer "synced" on the standard output once every command
//              before it is done
//   menu NAME  open the actions menu of the card named NAME
//   click TEXT click the visible link or button that reads TEXT
//   check-all  tick the checkbox that selects every item on the page
//   uncheck NAME  untick the checkbox of the item whose row mentions NAME
//
// The last four click in the page the way a presenter would, waiting up to
// five seconds for what they click to appear.
//
// Each change waits DEMO_BROWSER_DELAY seconds (default 1) first, so the
// browser changes after the terminal, not at the same time.
//
// On the fragments and design library screens it closes Liferay's product
// menu, if it is open, so their content gets the whole width.
//
// The Fragment API does not give a resource folder's id, which a folder's
// page needs, so a URL with demoOpenFolder=NAME opens the Resources tab
// it points at and then the folder of that name in it.
//
// It drives the most recently used tab, reconnecting when that tab changes,
// and ignores what it cannot do, so the demo goes on without a browser. It
// speaks the WebSocket protocol itself, as Node.js has no WebSocket client
// before version 22.

import {randomBytes} from 'node:crypto';
import http from 'node:http';
import {createInterface} from 'node:readline';

const port = process.env.DEMO_CDP_PORT || '9333';
const delay = Number(process.env.DEMO_BROWSER_DELAY ?? '1') * 1000;

const CLOSE_PRODUCT_MENU = `
	const folder = new URLSearchParams(location.search).get('demoOpenFolder');

	if (folder) {
		addEventListener('load', () => {
			let tries = 0;

			const open = () => {
				const link = [...document.querySelectorAll('a[href*="folderId"]')].find((candidate) => candidate.textContent.trim() === folder);

				if (link) {
					location.replace(link.href);
				}
				else if (++tries < 40) {
					setTimeout(open, 150);
				}
			};

			open();
		});
	}

	if (location.pathname.includes('/fragments/') || location.search.includes('DesignLibraryAdminPortlet')) {
		addEventListener('load', () => {
			let tries = 0;

			const close = () => {
				const slider = document.getElementById('_com_liferay_product_navigation_product_menu_web_portlet_ProductMenuPortlet_sidenavSliderId');
				const toggle = document.querySelector('[data-qa-id="productMenu"]');
				const sideNavigation = document.getElementById('com_liferay_application_list_taglib_side_navigation');
				const closeButton = document.querySelector('.control-menu-nav-link[aria-label="Close Product Menu"]');

				if (slider && toggle && window.Liferay?.SideNavigation?.instance(toggle)) {
					if (slider.classList.contains('open')) {
						Liferay.SideNavigation.hide(toggle);
					}

					return;
				}

				if (sideNavigation && closeButton) {
					if (!sideNavigation.classList.contains('c-slideout-show')) {
						return;
					}

					closeButton.click();
				}

				if (++tries < 40) {
					setTimeout(close, 150);
				}
			};

			close();
		});
	}
`;

const CLICK = {
	'check-all': () => document.querySelector('.management-bar input[type="checkbox"]:not([name])'),
	click: (text) => [...document.querySelectorAll('a, button')].find((element) => element.offsetParent !== null && element.textContent.trim() === text),
	uncheck: (name) => [...document.querySelectorAll('input[type="checkbox"]')].find((checkbox) => {
		if (!checkbox.checked) {
			return false;
		}

		let row = checkbox.parentElement;

		for (let level = 0; row && level < 8; level++, row = row.parentElement) {
			if (row.querySelectorAll('input[type="checkbox"]').length === 1 && row.textContent.includes(name)) {
				return true;
			}
		}

		return false;
	}),
	menu: (name) => [...document.querySelectorAll('.card')].find((card) => card.querySelector('.card-title')?.textContent.trim() === name)?.querySelector('button[aria-label="More actions"]'),
};

function click(command, argument) {
	return `(() => {
		const find = ${CLICK[command]};
		let tries = 0;

		const attempt = () => {
			const element = find(${JSON.stringify(argument)});

			if (element) {
				element.click();
			}
			else if (++tries < 50) {
				setTimeout(attempt, 100);
			}
		};

		attempt();
	})()`;
}

let socket = null;
let targetId = null;
let messageId = 0;

function open(url) {
	return new Promise((resolve, reject) => {
		const request = http.request(url.replace(/^ws:/, 'http:'), {
			headers: {
				'Connection': 'Upgrade',
				'Sec-WebSocket-Key': randomBytes(16).toString('base64'),
				'Sec-WebSocket-Version': '13',
				'Upgrade': 'websocket',
			},
		});

		request.on('upgrade', (response, upgraded) => {
			upgraded.on('data', () => {});
			upgraded.on('error', () => {});

			resolve(upgraded);
		});
		request.on('response', () => reject(new Error('No upgrade')));
		request.on('error', reject);
		request.end();
	});
}

async function connect() {
	const response = await fetch(`http://127.0.0.1:${port}/json/list`);
	const target = (await response.json()).find((candidate) => candidate.type === 'page' && !candidate.url.startsWith('devtools://'));

	if (!target) {
		throw new Error('No tab');
	}

	if (socket && !socket.destroyed && target.id === targetId) {
		return;
	}

	socket?.destroy();

	socket = await open(target.webSocketDebuggerUrl);
	targetId = target.id;

	send('Page.enable');
	send('Page.addScriptToEvaluateOnNewDocument', {source: CLOSE_PRODUCT_MENU});
}

function send(method, params = {}) {
	const payload = Buffer.from(JSON.stringify({id: ++messageId, method, params}));
	const mask = randomBytes(4);

	let header;

	if (payload.length < 126) {
		header = Buffer.from([0x81, 0x80 | payload.length]);
	}
	else if (payload.length < 65536) {
		header = Buffer.alloc(4);
		header.writeUInt8(0x81, 0);
		header.writeUInt8(0x80 | 126, 1);
		header.writeUInt16BE(payload.length, 2);
	}
	else {
		header = Buffer.alloc(10);
		header.writeUInt8(0x81, 0);
		header.writeUInt8(0x80 | 127, 1);
		header.writeBigUInt64BE(BigInt(payload.length), 2);
	}

	for (let i = 0; i < payload.length; i++) {
		payload[i] ^= mask[i % 4];
	}

	socket.write(Buffer.concat([header, mask, payload]));
}

const REVEAL = `(() => {
	const fragments = [...document.querySelectorAll('[class*="rays-"]')].filter((element) => [...element.classList].some((name) => /^rays-[a-z-]+$/.test(name)));
	const last = fragments[fragments.length - 1];

	if (last) {
		last.scrollIntoView({behavior: 'smooth', block: 'end'});
	}
	else {
		window.scrollTo({behavior: 'smooth', top: document.body.scrollHeight});
	}
})()`;

const revealText = (text) => `(() => {
	const start = Date.now();
	const find = () => {
		const element = [...document.querySelectorAll('body *')].find((candidate) => candidate.children.length === 0 && candidate.textContent.trim() === ${JSON.stringify(text)});

		if (element) {
			(element.closest('.card') || element).scrollIntoView({behavior: 'smooth', block: 'center'});
		}
		else if (Date.now() - start < 10000) {
			setTimeout(find, 300);
		}
	};

	find();
})()`;

for await (const line of createInterface({input: process.stdin})) {
	const [command, ...rest] = line.trim().split(' ');

	if (command === 'sync') {
		process.stdout.write('synced\n');

		continue;
	}

	if (command === 'wait') {
		await new Promise((resolve) => setTimeout(resolve, Number(rest[0]) * 1000));

		continue;
	}

	try {
		await new Promise((resolve) => setTimeout(resolve, delay));
		await connect();

		if (command === 'goto') {
			send('Page.navigate', {url: rest.join(' ')});
		}
		else if (command === 'reload') {
			send('Page.reload', {ignoreCache: false});
		}
		else if (command === 'reveal') {
			send('Runtime.evaluate', {expression: rest.length ? revealText(rest.join(' ')) : REVEAL});
		}
		else if (command in CLICK) {
			send('Runtime.evaluate', {expression: click(command, rest.join(' '))});
		}
	}
	catch {
		socket = null;
		targetId = null;
	}
}
