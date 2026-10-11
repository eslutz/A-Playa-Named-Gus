from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlparse,parse_qs
from pathlib import Path
import json,re,subprocess
class Capture(BaseHTTPRequestHandler):
 def do_GET(self):
  args=parse_qs(urlparse(self.path).query);device=args.get('device',[''])[0];name=args.get('name',[''])[0]
  mapping=json.loads(Path('/tmp/gus-ui-runtime/capture-map.json').read_text())
  if device not in mapping or not re.fullmatch('[a-z0-9-]+',name):
   self.send_error(400);return
  out=Path(mapping[device]);out.mkdir(parents=True,exist_ok=True)
  r=subprocess.run(['xcrun','simctl','io',device,'screenshot',str(out/(name+'.png'))],capture_output=True,timeout=45)
  self.send_response(200 if r.returncode==0 else 500);self.end_headers();self.wfile.write(b'captured' if r.returncode==0 else b'capture failed')
  print(device,name,r.returncode,flush=True)
 def log_message(self,*args):pass
ThreadingHTTPServer(('127.0.0.1',8097),Capture).serve_forever()
