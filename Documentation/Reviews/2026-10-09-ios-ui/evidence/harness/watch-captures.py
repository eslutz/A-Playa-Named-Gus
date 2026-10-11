import sys,time,pathlib,subprocess,re
log=pathlib.Path(sys.argv[1]);device=sys.argv[2];out=pathlib.Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=True);seen=set()
start=time.time()
while time.time()-start<480:
 text=log.read_text(errors='replace') if log.exists() else ''
 for name in re.findall(r'^CAPTURE_READY ([a-z0-9-]+)$',text,re.M):
  if name in seen:continue
  seen.add(name);time.sleep(.5)
  subprocess.run(['xcrun','simctl','io',device,'screenshot',str(out/(name+'.png'))],check=True)
 if '** TEST SUCCEEDED **' in text or '** TEST FAILED **' in text:break
 time.sleep(.3)
print('Captured',sorted(seen))
