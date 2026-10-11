from pathlib import Path
import subprocess,json,time,os
out=Path('/tmp/gus-final-profiles');out.mkdir(exist_ok=True)
device='0091C2E3-7B8A-4452-B708-095D613AEB3A';bundle='dev.ericslutz.gus'
movie=json.loads(Path('/tmp/gus-state-validation/Tests/fixture.json').read_text())['movie']
launchEnv=dict(os.environ,GUS_LAUNCH_APP_PATH='/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus/build/release-validation-audit/Build/Products/Debug-iphonesimulator/A Playa Named Gus.app')
with open('/tmp/gus-final-launch-corrected.log','w') as stream:
 subprocess.run(['Scripts/measure-launch-baseline.sh',device,'5'],env=launchEnv,stdout=stream,stderr=subprocess.STDOUT,check=True)
results=[]
for name,template in [('swiftui','SwiftUI'),('time-profiler','Time Profiler'),('leaks','Leaks')]:
 subprocess.run(['xcrun','simctl','terminate',device,bundle],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 launch=subprocess.check_output(['xcrun','simctl','launch',device,bundle,'--gus-demo-server','--gus-route','item/'+movie],text=True)
 pid=launch.strip().split(':')[-1].strip();time.sleep(2)
 cmd=['xcrun','xctrace','record','--template',template,'--device',device,'--attach',pid,'--time-limit','20s','--output',str(out/(name+'.trace')),'--no-prompt']
 with (out/(name+'.log')).open('w') as stream:
  r=subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT,timeout=150)
 e=dict(name=name,template=template,exitCode=r.returncode,scope='20 seconds of foreground movie-detail request after two-second settle; simulator Debug; no energy, interaction peak or first-frame claim')
 if r.returncode==0:
  exp=subprocess.run(['xcrun','xctrace','export','--input',str(out/(name+'.trace')),'--toc','--output',str(out/(name+'-toc.xml'))],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=60);e['tocExitCode']=exp.returncode
  if exp.returncode: (out/(name+'-export.log')).write_text(exp.stdout)
 results.append(e);(out/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(e),flush=True)
subprocess.run(['xcrun','simctl','terminate',device,bundle],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
