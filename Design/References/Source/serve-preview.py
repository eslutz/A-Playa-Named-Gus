"""Read-only loopback server for the approved synthetic design preview only."""
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse,unquote
import re,mimetypes
ROOT=Path(__file__).resolve().parents[2]
class PreviewHandler(BaseHTTPRequestHandler):
 def do_GET(self):self.serve(False)
 def do_HEAD(self):self.serve(True)
 def serve(self,head):
  name=unquote(urlparse(self.path).path).lstrip('/') or 'Exports/Preview/Preview.html'
  allowed=name in {'Exports/Preview/Preview.html','DISCOVER.md'} or re.fullmatch(r'Exports/Preview/preview-scenes/[A-Za-z0-9-]+\.js',name) or re.fullmatch(r'Gus/[A-Za-z0-9-]+/(Light|Dark)/[A-Za-z0-9 -]+\.fig',name)
  path=ROOT/name
  if not allowed or path.is_symlink() or ROOT not in path.resolve().parents or not path.is_file():self.send_error(404);return
  data=path.read_bytes();self.send_response(200);self.send_header('Content-Type',(mimetypes.guess_type(name)[0] or 'application/octet-stream')+'; charset=utf-8');self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; frame-ancestors 'none'; base-uri 'none'");self.end_headers()
  if not head:self.wfile.write(data)
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),PreviewHandler)
print(f'http://127.0.0.1:{server.server_port}/Exports/Preview/Preview.html',flush=True)
try:server.serve_forever()
except KeyboardInterrupt:pass
finally:server.server_close()
