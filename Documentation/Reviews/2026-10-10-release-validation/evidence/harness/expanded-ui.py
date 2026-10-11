from pathlib import Path
import importlib.util,json,subprocess
root=Path('/tmp/gus-staged-candidate'); out=Path('/tmp/gus-ui-extra-validation');out.mkdir(exist_ok=True)
s=importlib.util.spec_from_file_location('v',root/'Scripts/validate-release.py');v=importlib.util.module_from_spec(s);s.loader.exec_module(v)
products=Path('/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus/build/release-validation-audit/Build/Products')
results=[]
def lane(name,scheme,device,tests):
 command=['xcodebuild','-project','A Playa Named Gus.xcodeproj','-scheme',scheme,'-derivedDataPath',str(products.parents[1]),'-onlyUsePackageVersionsFromResolvedFile','ONLY_ACTIVE_ARCH=YES','-destination','id='+device,'-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-resultBundlePath',str(out/(name+'.xcresult')),'test']+['-only-testing:'+t for t in tests]
 try:v.run(command,root,out,name,results)
 except RuntimeError:pass
main='0091C2E3-7B8A-4452-B708-095D613AEB3A'
subprocess.run(['xcrun','simctl','boot',main],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['xcrun','simctl','bootstatus',main,'-b'],check=True,stdout=subprocess.DEVNULL)
options={'appearance':'dark','increase_contrast':'enabled','content_size':'accessibility-extra-extra-extra-large'}
baseline={k:subprocess.check_output(['xcrun','simctl','ui',main,k],text=True).strip() for k in options}
(out/'appearance-baseline.json').write_text(json.dumps(baseline,indent=2)+'\n')
assert all(value not in ('unknown','unsupported') for value in baseline.values()), baseline
try:
 for k,value in options.items():subprocess.run(['xcrun','simctl','ui',main,k,value],check=True)
 lane('iphone-dark-contrast-ax5','Gus iOS Tests',main,['GusUITests/GusAuthenticatedUITests/testLargestTextAuthenticatedDetails','GusUITests/GusAuthenticatedUITests/testFullSynopsisHeading','GusUITests/GusAuthenticatedUITests/testDetailCurrentScreenAccessibility','GusUITests/GusAuthenticatedUITests/testAudioCloseAndReopen'])
finally:
 for k,value in baseline.items():
  if value not in ('unsupported','unknown'):subprocess.run(['xcrun','simctl','ui',main,k,value],check=True)
 restored={k:subprocess.check_output(['xcrun','simctl','ui',main,k],text=True).strip() for k in options}
 (out/'appearance-restored.json').write_text(json.dumps(restored,indent=2)+'\n')
 assert restored==baseline
lane('iphone-narrow-se','Gus iOS Tests','3BB872EF-4DDD-4002-B9A8-7E0BF6D9B261',['GusUITests/GusAuthenticatedUITests/testLargestTextAuthenticatedDetails','GusUITests/GusAuthenticatedUITests/testBookReaderDismissal','GusUITests/GusAuthenticatedUITests/testAudioCloseAndReopen','GusUITests/GusAuthenticatedUITests/testLoadedDetailLayouts','GusUITests/GusLaunchUITests/testConnectScreenRendersAtLargestAccessibilityContentSize','GusUITests/GusAuthenticatedUITests/testConnectCurrentScreenAccessibility'])
lane('iphone-large','Gus iOS Tests','7889A486-07F4-4BE9-B92A-903BA2C1A1E9',['GusUITests/GusAuthenticatedUITests/testLoadedDetailLayouts','GusUITests/GusAuthenticatedUITests/testAudioCloseAndReopen'])
lane('ipad-mini','Gus iOS Tests','4B7E6FD5-C808-4263-9CCA-764AD6A6BE3D',['GusUITests/GusAuthenticatedUITests/testLoadedDetailLayouts','GusUITests/GusAuthenticatedUITests/testBookReaderDismissal'])
lane('tv-1080p','Gus tvOS Tests','07FA9453-0F67-4F99-AA46-7799B3883D6E',['GusTVOSUITests/GusAuthenticatedUITests'])
lane('watch-large','Gus watchOS Tests','8C9755E0-E888-4295-BF31-231C61FC31A3',['GusWatchUITests/WatchBrowseUITests'])
lane('ios-26-fallback','Gus iOS Tests','A1ACA0A5-5E8F-4CB6-860A-A598500308DA',['GusUITests/GusAuthenticatedUITests/testAudioCloseAndReopen','GusUITests/GusAuthenticatedUITests/testLoadedDetailLayouts'])
print(json.dumps([{k:r.get(k) for k in ('name','exitCode','tests','seconds')} for r in results],indent=2))

# Same final app, independent UI-only capture harness; synchronous native IO pixels.
vision='1711D519-F8C9-42CA-A705-5F12E87D96F2'
subprocess.run(['xcrun','simctl','boot',vision],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['xcrun','simctl','bootstatus',vision,'-b'],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['xcrun','simctl','install',vision,str(products/'Debug-xrsimulator/A Playa Named Gus.app')],check=True)
command=['xcodebuild','-project','GusVisionCapture.xcodeproj','-scheme','GusVisionCapture','-destination','id='+vision,'-derivedDataPath','/tmp/gus-vision-capture-derived','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-resultBundlePath',str(out/'vision-native-capture.xcresult'),'-only-testing:GusVisionCaptureUITests/GusAuthenticatedUITests/testAudioCloseAndReopen','-only-testing:GusVisionCaptureUITests/GusAuthenticatedUITests/testLoadedDetailLayouts','test']
try:v.run(command,Path('/tmp/gus-vision-capture-validation'),out,'vision-native-capture',results)
except RuntimeError:pass
