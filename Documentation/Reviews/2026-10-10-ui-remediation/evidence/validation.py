import subprocess,json,time
from pathlib import Path
out=Path('build/validation/ui-remediation-2026-10-10-complete');out.mkdir(parents=True,exist_ok=True)
lanes=[('ios','Gus iOS Unit Tests','platform=iOS Simulator,id=8D6A5B35-B67B-4725-B428-DC0EAA80797D','test'),('ipad','A Playa Named Gus','platform=iOS Simulator,id=4B7E6FD5-C808-4263-9CCA-764AD6A6BE3D','build'),('mac','Gus macOS Unit Tests','platform=macOS','test'),('tv','Gus tvOS Unit Tests','platform=tvOS Simulator,id=07FA9453-0F67-4F99-AA46-7799B3883D6E','test'),('vision','Gus visionOS Unit Tests','platform=visionOS Simulator,id=1711D519-F8C9-42CA-A705-5F12E87D96F2','test'),('watch','Gus watchOS','platform=watchOS Simulator,id=42BB7891-1C89-4DF7-A7F7-5CF4A9C71326','build')]
results=[]
for name,scheme,destination,action in lanes:
 print('Starting',name,flush=True)
 start=time.monotonic()
 cmd=['xcodebuild','-project','A Playa Named Gus.xcodeproj','-scheme',scheme,'-destination',destination,'-derivedDataPath','build/DerivedData','ONLY_ACTIVE_ARCH=YES',action]
 with (out/(name+'.log')).open('w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
 results.append(dict(lane=name,command=cmd,exitCode=r.returncode,seconds=round(time.monotonic()-start,1)))
 (out/'results.json').write_text(json.dumps(results,indent=2))
 print(name,'finished with',r.returncode,flush=True)
