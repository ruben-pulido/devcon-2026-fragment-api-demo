// Moves the demo browser (demo/browser.sh) along with demo.sh, through
// Chrome's DevTools protocol on DEMO_CDP_PORT (default 9333). It reads one
// command per line on its standard input:
//
//   goto URL   show URL in the tab on display
//   reload     reload the tab on display
//
// It drives the most recently used tab, reconnecting when that tab changes,
// and ignores what it cannot do, so the demo goes on without a browser.

import {createInterface} from 'node:readline';

const port = process.env.DEMO_CDP_PORT || '9333';

let socket = null;
let targetId = null;
let messageId = 0;

async function connect() {
	const response = await fetch(`http://127.0.0.1:${port}/json/list`);
	const target = (await response.json()).find((candidate) => candidate.type === 'page' && !candidate.url.startsWith('devtools://'));

	if (!target) {
		throw new Error('No tab');
	}

	if (socket && socket.readyState === WebSocket.OPEN && target.id === targetId) {
		return;
	}

	socket?.close();

	socket = new WebSocket(target.webSocketDebuggerUrl);
	targetId = target.id;

	await new Promise((resolve, reject) => {
		socket.onopen = resolve;
		socket.onerror = reject;
	});
}

function send(method, params = {}) {
	socket.send(JSON.stringify({id: ++messageId, method, params}));
}

for await (const line of createInterface({input: process.stdin})) {
	const [command, ...rest] = line.trim().split(' ');

	try {
		await connect();

		if (command === 'goto') {
			send('Page.navigate', {url: rest.join(' ')});
		}
		else if (command === 'reload') {
			send('Page.reload', {ignoreCache: false});
		}
	}
	catch {
		socket = null;
		targetId = null;
	}
}
