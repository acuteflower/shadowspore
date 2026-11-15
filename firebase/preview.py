"""Local preview, including correct ES-module MIME types on Windows."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=4180)
parser.add_argument('--account-fixture', action='store_true', help='Local-only fake account for browser QA; never deployed')
args = parser.parse_args()
SimpleHTTPRequestHandler.extensions_map['.mjs'] = 'application/javascript'
root = Path(__file__).parent


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split('?')[0]
        if args.account_fixture and path in ('/', '/index.html', '/__test/account-fixture.js'):
            if path == '/__test/account-fixture.js':
                content = (root / 'tests' / 'account-fixture.js').read_bytes()
                content_type = 'application/javascript'
            else:
                source = (root / 'public' / 'index.html').read_text(encoding='utf-8-sig')
                content = source.replace('<script type="module"', '<script src="/__test/account-fixture.js"></script><script type="module"').encode()
                content_type = 'text/html; charset=utf-8'
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(content)
            return
        super().do_GET()


handler = partial(Handler, directory=str(root / 'public'))
print(f'http://127.0.0.1:{args.port}', flush=True)
ThreadingHTTPServer(('127.0.0.1', args.port), handler).serve_forever()
