#!/usr/bin/env python3
# The store grid: every DevCon city's store page, in a 2 x 4 grid, at
# http://localhost:8090 (GRID_PORT), or only some of them, one under another, as in
# http://localhost:8090/?cities=Madrid,London. A tile shows up as soon as its
# store page exists and reloads when the page changes, so act 5 fills the
# grid and the propagation in act 6 turns every tile to winter.
#
#   demo/store-grid.py
#
# Liferay only lets its own pages frame its pages, so this server proxies the
# portal (LIFERAY_URL) next to the grid page, without the X-Frame-Options
# header.

import http.server
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIFERAY_URL = os.environ.get('LIFERAY_URL', 'http://localhost:8080').rstrip('/')
PORT = int(os.environ.get('GRID_PORT', '8090'))

HOP_BY_HOP = {'connection', 'content-length', 'keep-alive', 'transfer-encoding', 'x-frame-options'}


def cities():
	output = subprocess.run(
		['bash', '-c', 'source "$1/lib.sh"; printf "%s\\n" "${DEVCON_CITIES[@]}"', '-', ROOT],
		capture_output=True, check=True, text=True).stdout

	return [line.split('|') for line in output.splitlines() if line]


def grid_page(query):
	selected = [name for name in urllib.parse.parse_qs(query).get('cities', [''])[0].split(',') if name]
	shown = [city for city in cities() if not selected or city[2] in selected]

	tiles = ''.join(
		f'<div class="tile" data-path="/web/ray-s-coffee-{re.sub("[^a-z]", "-", city.lower())}/store-home">'
		f'<div class="label"><b>{year}</b> {city}</div>'
		f'<div class="frame"><div class="empty">Opening soon</div></div></div>'
		for year, _, city, _, _ in shown)

	with open(os.path.join(ROOT, 'demo', 'store-grid.html'), encoding='utf-8') as file:
		columns = 1 if selected else 2

		return file.read().replace('<!-- tiles -->', tiles).replace('--columns: 2', f'--columns: {columns}').replace('--rows: 4', f'--rows: {(len(shown) + columns - 1) // columns}').encode('utf-8')


class Handler(http.server.BaseHTTPRequestHandler):

	def do_GET(self):
		path, _, query = self.path.partition('?')

		if path in ('/', '/index.html'):
			body = grid_page(query)

			self.send_response(200)
			self.send_header('Cache-Control', 'no-store')
			self.send_header('Content-Length', str(len(body)))
			self.send_header('Content-Type', 'text/html; charset=utf-8')
			self.end_headers()
			self.wfile.write(body)

			return

		request = urllib.request.Request(
			LIFERAY_URL + self.path,
			headers={key: value for key, value in self.headers.items() if key.lower() not in ('host', 'accept-encoding')})

		try:
			response = urllib.request.urlopen(request, timeout=30)
		except urllib.error.HTTPError as error:
			response = error

		body = response.read()

		self.send_response(response.status)

		for key, value in response.headers.items():
			if key.lower() not in HOP_BY_HOP:
				self.send_header(key, value)

		self.send_header('Content-Length', str(len(body)))
		self.end_headers()
		self.wfile.write(body)

	def log_message(self, format, *args):
		pass


print(f'Store grid at http://localhost:{PORT}')

http.server.ThreadingHTTPServer(('', PORT), Handler).serve_forever()
