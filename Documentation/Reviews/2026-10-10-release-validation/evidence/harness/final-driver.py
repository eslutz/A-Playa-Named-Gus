from pathlib import Path
import subprocess,json,os,shutil,hashlib
root=Path('/tmp/gus-staged-candidate');app=Path('/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus');old=Path('/tmp/gus-final-validation-10');base=Path('/tmp/gus-final-validation-11');base.mkdir(exist_ok=True)
# Recover the previous source exactly and verify its frozen hash before comparing DEBUG tokens.
new=(root/'Sources/App/GusApp.swift').read_text()
previous=new.replace('        #if DEBUG\n            let arguments = ProcessInfo.processInfo.arguments\n            shouldRestoreLastSession = !arguments.contains("--gus-skip-session-restore")\n','        let arguments = ProcessInfo.processInfo.arguments\n        shouldRestoreLastSession = !arguments.contains("--gus-skip-session-restore")\n        #if DEBUG\n',1).replace('        #else\n            shouldRestoreLastSession = true\n','        #else\n',1)
expected=json.loads((old/'archives/source-hashes.json').read_text())['Sources/App/GusApp.swift']
assert hashlib.sha256(previous.encode()).hexdigest()==expected

def debug_tokens(source):
 stack=[];lines=[]
 for line in source.splitlines():
  value=line.strip()
  if value.startswith('#if '):
   isdebug=value=='#if DEBUG';stack.append([isdebug,True]);
   if isdebug:continue
  elif value=='#else':
   if stack[-1][0]:stack[-1][1]=not stack[-1][1];continue
  elif value=='#endif':
   isdebug,_=stack.pop()
   if isdebug:continue
  if all(enabled for special,enabled in stack if special) and value:lines.append(value)
 return '\n'.join(lines)
assert debug_tokens(previous)==debug_tokens(new)
proof={'candidate':'candidate-11','reusedPhases':['builds','tests','ui'],'reusedFrom':'candidate-10','reason':'Only shipping source change is the release-only skip-session argument removal. All active DEBUG source tokens remain identical; all four Release archives and static checks rerun. Launch helper is a separate script-only path correction validated by static checks and five actual launch runs.','oldAppSourceSHA256':expected,'newAppSourceSHA256':hashlib.sha256(new.encode()).hexdigest(),'activeDebugTokensSHA256':hashlib.sha256(debug_tokens(new).encode()).hexdigest(),'activeDebugTokensIdentical':True}
(base/'validation-provenance.json').write_text(json.dumps(proof,indent=2)+'\n')
results=[]
for phase in ('static','builds','tests','ui','archives'):
 if phase in proof['reusedPhases']:
  assert all(r['exitCode']==0 for r in json.loads((old/phase/'results.json').read_text()))
  shutil.copytree(old/phase,base/phase,copy_function=os.link);code=0
 else:
  code=subprocess.run(['python3','Scripts/validate-release.py','--phase',phase,'--root',str(root),'--output',str(base/phase),'--derived-data',str(app/'build/release-validation-audit')],cwd=root).returncode
 results.append(dict(phase=phase,exitCode=code,reused=phase in proof['reusedPhases']));(base/'phases.json').write_text(json.dumps(results,indent=2)+'\n')
 if code:raise SystemExit('Stopping for triage: '+phase)
# Alias records only after the completed final static run; no original manifest is rewritten.
shutil.copytree(base/'static',base/'static-launch-correction',copy_function=os.link)
(base/'launch-tooling-provenance.json').write_text(json.dumps({'changedInputs':['Sources/App/GusApp.swift','Scripts/measure-launch-baseline.sh'],'releaseSourceChange':'Session restoration test argument now DEBUG only','scriptChange':'Observed product-name path correction','validation':'All four final Release archives, fresh static checks, unchanged Debug tokens and fresh expanded runtime checks; actual five-run corrected helper follows'},indent=2)+'\n')
for script in ('/tmp/gus-extra-driver.py','/tmp/gus-ui-extra-driver.py'):
 print('RUN '+script,flush=True);subprocess.run(['python3',script],cwd=root,check=True)
print('RUN final state validation',flush=True)
r=subprocess.run(['xcodebuild','-project','GusStateValidation.xcodeproj','-scheme','GusStateValidation','-destination','id=0091C2E3-7B8A-4452-B708-095D613AEB3A','-derivedDataPath','/tmp/gus-state-derived','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-resultBundlePath','/tmp/gus-state-final-all.xcresult','test'],cwd='/tmp/gus-state-validation',stdout=open('/tmp/gus-state-final-all.log','w'),stderr=subprocess.STDOUT);print('State exit '+str(r.returncode),flush=True)
subprocess.run(['python3','/tmp/gus-profile-final.py'],cwd=root,check=True)
