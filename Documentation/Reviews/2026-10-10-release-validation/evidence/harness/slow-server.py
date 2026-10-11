from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json,time
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  time.sleep(10)
  body=json.dumps(dict(ProductName="Jellyfin Server",ServerName="Validation fixture",Id="validation-slow",Version="10.11.0")).encode()
  try:
   self.send_response(200);self.send_header("Content-Type","application/json");self.end_headers();self.wfile.write(body)
  except (BrokenPipeError,ConnectionResetError):pass
print("Validation-only slow fixture listening on localhost:8098",flush=True)
ThreadingHTTPServer(("127.0.0.1",8098),Handler).serve_forever()
