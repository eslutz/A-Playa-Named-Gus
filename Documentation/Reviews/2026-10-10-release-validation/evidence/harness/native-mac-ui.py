from pathlib import Path
import importlib.util,json
root=Path('/tmp/gus-staged-candidate');out=Path('/tmp/gus-mac-ui-final');out.mkdir(exist_ok=True)
spec=importlib.util.spec_from_file_location('v',root/'Scripts/validate-release.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v);results=[]
command=['xcodebuild','-project','A Playa Named Gus.xcodeproj','-scheme','Gus macOS Tests','-destination','platform=macOS','-derivedDataPath','/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus/build/release-validation-audit','-onlyUsePackageVersionsFromResolvedFile','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-only-testing:GusMacOSUITests','-resultBundlePath',str(out/'mac-ui.xcresult'),'test']
try:v.run(command,root,out,'mac-ui',results)
except RuntimeError:pass
print(json.dumps(results,indent=2))
