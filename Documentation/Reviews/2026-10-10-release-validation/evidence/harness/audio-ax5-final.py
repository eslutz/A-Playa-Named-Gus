from pathlib import Path
import subprocess,importlib.util,json
root=Path('/tmp/gus-staged-candidate');out=Path('/tmp/gus-ui-extra-validation');results=json.loads((out/'results.json').read_text())
spec=importlib.util.spec_from_file_location('v',root/'Scripts/validate-release.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
device='0091C2E3-7B8A-4452-B708-095D613AEB3A';product='/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus/build/release-validation-audit/Build/Products/Debug-iphonesimulator/A Playa Named Gus.app'
subprocess.run(['xcrun','simctl','boot',device],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);subprocess.run(['xcrun','simctl','bootstatus',device,'-b'],check=True,stdout=subprocess.DEVNULL);subprocess.run(['xcrun','simctl','install',device,product],check=True)
command=['xcodebuild','-project','GusAudioAX5Validation.xcodeproj','-scheme','GusAudioAX5Validation','-destination','id='+device,'-derivedDataPath','/tmp/gus-audio-ax5-derived','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-resultBundlePath',str(out/'audio-ax5-landscape.xcresult'),'-only-testing:GusAudioAX5UITests/GusAuthenticatedUITests/testAudioLargestTextLandscapeTransportReachability','test']
v.run(command,Path('/tmp/gus-audio-ax5-validation'),out,'audio-ax5-landscape',results)
