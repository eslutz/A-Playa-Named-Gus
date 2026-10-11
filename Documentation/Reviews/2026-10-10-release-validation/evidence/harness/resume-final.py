from pathlib import Path
import subprocess,json,importlib.util,shutil
root=Path('/tmp/gus-staged-candidate');out=Path('/tmp/gus-extra-validation');history=out/'history';history.mkdir(exist_ok=True)
rows=json.loads((out/'results.json').read_text());failed=[r for r in rows if r['exitCode']];assert len(failed)==1 and failed[0]['name']=='release-performance'
(history/'performance-attempt.json').write_text(json.dumps(failed,indent=2)+'\n')
for p in list(out.glob('release-performance*')):shutil.move(str(p),str(history/p.name))
rows=[r for r in rows if not r['exitCode']];(out/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
spec=importlib.util.spec_from_file_location('v',root/'Scripts/validate-release.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
command=['xcodebuild','-project','A Playa Named Gus.xcodeproj','-derivedDataPath','/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus/build/release-validation-audit','-onlyUsePackageVersionsFromResolvedFile','ONLY_ACTIVE_ARCH=YES','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-scheme','Gus macOS Unit Tests','-destination','platform=macOS','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','-configuration','Release','ENABLE_TESTABILITY=YES','-enableCodeCoverage','NO','-only-testing:GusMacOSTests/PerformanceMeasurementTests','-resultBundlePath',str(out/'release-performance-fixed.xcresult'),'test']
v.run(command,root,out,'release-performance-fixed',rows)
print('RUN boot-corrected expanded UI',flush=True);subprocess.run(['python3','/tmp/gus-ui-extra-driver.py'],cwd=root,check=True)
print('RUN final state validation',flush=True)
r=subprocess.run(['xcodebuild','-project','GusStateValidation.xcodeproj','-scheme','GusStateValidation','-destination','id=0091C2E3-7B8A-4452-B708-095D613AEB3A','-derivedDataPath','/tmp/gus-state-derived','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-resultBundlePath','/tmp/gus-state-final-all.xcresult','test'],cwd='/tmp/gus-state-validation',stdout=open('/tmp/gus-state-final-all.log','w'),stderr=subprocess.STDOUT);print('State exit '+str(r.returncode),flush=True)
subprocess.run(['python3','/tmp/gus-profile-final.py'],cwd=root,check=True)
