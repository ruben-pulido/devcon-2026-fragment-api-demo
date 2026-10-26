// Moves the demo browser (demo/browser.sh) along with demo.sh, through
// Chrome's DevTools protocol on DEMO_CDP_PORT (default 9333). It reads one
// command per line on its standard input:
//
//   goto URL   show URL in the tab on display
//   reload     reload the tab on display
//
// It drives the most recently used tab, reconnecting when that tab changes,
// and ignores what it cannot do, so the demo goes on without a browser. It
// speaks the WebSocket protocol itself, as Node.js has no WebSocket client
// before version 22.

import {randomBytes} from 'node:crypto';
import http from 'node:http';
import {createInterface} from 'node:readline';

const port = process.env.DEMO_CDP_PORT || '9333';

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
