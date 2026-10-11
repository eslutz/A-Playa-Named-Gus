from pathlib import Path
import time,subprocess,json,hashlib,re
out=Path('/tmp/gus-vision-native-final');out.mkdir(exist_ok=True)
log=Path('/tmp/gus-final-validation-10/ui/ui-vision.log')
device='1711D519-F8C9-42CA-A705-5F12E87D96F2'
seen=set();results=[];deadline=time.monotonic()+2400
while time.monotonic()<deadline:
    if log.exists():
        text=log.read_text(errors='replace')
        for name in re.findall(r"Added attachment named '([^']+)'",text):
            if name in seen:continue
            seen.add(name)
            destination=out/(name+'.png')
            command=['xcrun','simctl','io',device,'screenshot',str(destination)]
            begin=time.time()
            r=subprocess.run(command,capture_output=True,text=True,timeout=30)
            entry={'name':name,'command':command,'captureRequestEpoch':begin,'captureEndEpoch':time.time(),'exitCode':r.returncode,'scope':'Read-only native simulator capture triggered by passed-test capture marker; rendered state requires independent image inspection, not an exact timestamp equivalence claim.'}
            if r.returncode==0 and destination.exists():entry.update(file=destination.name,sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),bytes=destination.stat().st_size)
            else:entry['error']=r.stderr.strip()
            results.append(entry);(out/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(name,r.returncode,flush=True)
        if '** TEST SUCCEEDED **' in text or '** TEST FAILED **' in text:break
    time.sleep(.1)
else:raise SystemExit('No completed native Vision UI run within bounded observation window')
