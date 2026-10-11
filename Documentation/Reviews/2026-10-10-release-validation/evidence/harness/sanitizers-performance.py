from pathlib import Path
import importlib.util, json, subprocess
root=Path('/tmp/gus-staged-candidate')
out=Path('/tmp/gus-extra-validation'); out.mkdir(exist_ok=True)
spec=importlib.util.spec_from_file_location('validation',root/'Scripts/validate-release.py')
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
results=[]
base=['xcodebuild','-project','A Playa Named Gus.xcodeproj','-derivedDataPath','/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus/build/release-validation-audit','-onlyUsePackageVersionsFromResolvedFile','ONLY_ACTIVE_ARCH=YES','-parallel-testing-enabled','NO','-collect-test-diagnostics','never']
for name,args in [
 ('mac-thread-sanitizer',['-scheme','Gus macOS Unit Tests','-destination','platform=macOS','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','-enableThreadSanitizer','YES']),
 ('mac-address-sanitizer',['-scheme','Gus macOS Unit Tests','-destination','platform=macOS','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','-enableAddressSanitizer','YES']),
 ('release-performance',['-scheme','Gus macOS Unit Tests','-destination','platform=macOS','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','-configuration','Release','-only-testing:GusMacOSTests/PerformanceMeasurementTests']),
]:
 try:v.run(base+args+['-resultBundlePath',str(out/(name+'.xcresult')),'test'],root,out,name,results)
 except RuntimeError:pass
print(json.dumps([{k:r.get(k) for k in ('name','exitCode','tests','seconds')} for r in results],indent=2))
