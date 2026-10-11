from pathlib import Path
import subprocess,json,time,xml.etree.ElementTree as E
out=Path('/tmp/gus-final-profiles');device='0091C2E3-7B8A-4452-B708-095D613AEB3A';bundle='dev.ericslutz.gus';movie=json.loads(Path('/tmp/gus-state-validation/Tests/fixture.json').read_text())['movie'];rows=json.loads((out/'results.json').read_text())
for name,extra in [('swiftui-compatible',['--template','Time Profiler','--instrument','SwiftUI']),('leaks-launch',['--template','Leaks'])]:
 subprocess.run(['xcrun','simctl','terminate',device,bundle],capture_output=True)
 if name=='swiftui-compatible':
  pid=subprocess.check_output(['xcrun','simctl','launch',device,bundle,'--gus-demo-server','--gus-route','item/'+movie],text=True).strip().split(':')[-1].strip();time.sleep(2);target=['--attach',pid]
 else:
  target=['--launch','--','/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus/build/release-validation-audit/Build/Products/Debug-iphonesimulator/A Playa Named Gus.app','--gus-demo-server','--gus-route','item/'+movie]
 cmd=['xcrun','xctrace','record',*extra,'--device',device,'--time-limit','20s','--output',str(out/(name+'.trace')),'--no-prompt',*target]
 with (out/(name+'.log')).open('w') as f:r=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=150)
 row=dict(name=name,exitCode=r.returncode,command=cmd,scope='Simulator Debug; movie detail requested; no interaction peak, energy, first-frame or leak-soak claim')
 if r.returncode==0:
  export=subprocess.run(['xcrun','xctrace','export','--input',str(out/(name+'.trace')),'--toc','--output',str(out/(name+'-toc.xml'))],capture_output=True,text=True,timeout=60);row['tocExitCode']=export.returncode
  if export.returncode==0:row['schemas']=sorted(set(n.get('schema') for n in E.parse(out/(name+'-toc.xml')).findall('.//table')))
 rows.append(row);(out/'results.json').write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(row),flush=True)
subprocess.run(['xcrun','simctl','terminate',device,bundle],capture_output=True)
