import subprocess,pathlib,sys
extra=len(sys.argv)>1
base=pathlib.Path('/tmp/gus-multiplatform-audit');udid='4B7E6FD5-C808-4263-9CCA-764AD6A6BE3D'
out=pathlib.Path.cwd()/'Documentation/Reviews/2026-10-09-ios-ui/evidence/multiplatform-2026-10-10/ipad-direct';out.mkdir(exist_ok=True)
subprocess.run(['xcodegen','generate','--spec',str(base/'project.yml'),'--project',str(base)],check=True)
cmd=['xcodebuild','test','-project',str(base/'GusSimulatorAudit.xcodeproj'),'-scheme','PadAudit','-destination','platform=iOS Simulator,id='+udid,'-derivedDataPath',str(base/'build'),'-only-testing:PadAudit/Landscape/'+('testExtra' if extra else 'testDirect'),'-resultBundlePath',str(base/('ipad-direct-extra.xcresult' if extra else 'ipad-direct.xcresult'))]
p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
with open(base/('ipad-direct-extra.log' if extra else 'ipad-direct.log'),'w') as log:
 for line in p.stdout:
  log.write(line);log.flush()
  if line.startswith('DIRECT_CAPTURE '):
   name=line.strip().split()[-1]
   subprocess.run(['xcrun','simctl','io',udid,'screenshot',str(out/(name+'-landscape.png'))],check=True)
print('Exit',p.wait())
