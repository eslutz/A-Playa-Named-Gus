"""Sequential font and raster checks for the integrated Discover proposal."""
from pathlib import Path
import json
import subprocess
import sys

base=Path(__file__).resolve().parents[2]
manifest=json.loads((base/'Source/discover/manifest.json').read_text())
cli=base/'Source/openpencil'
qa=base/'QA/Discover'
proofs=qa/'Previews'
proofs.mkdir(parents=True,exist_ok=True)
fonts=[]
for file in dict.fromkeys(s['file'] for s in manifest):
    result=subprocess.run([str(cli),'fonts',str(base/'../Gus'/file),'--json'],capture_output=True,text=True,timeout=60)
    if result.returncode:raise RuntimeError(result.stderr)
    report=json.loads(result.stdout)
    assert report['faithful'] and not report['issues'],file
    fonts.append({'file':file,**report})
    print('Fonts PASS: '+file,flush=True)
(qa/'fonts.json').write_text(json.dumps(fonts,indent=2))
selected=manifest
expected={f"{s['device'].replace(' ','-')}-{s['theme']}-{s['state']}.png" for s in selected}
for old in proofs.glob('*.png'):
    if old.name not in expected:old.unlink()
results=[]
unchanged=set()
if '--reuse-unchanged' in sys.argv:
    integration=json.loads((qa/'integration.json').read_text())
    unchanged={k for f in integration['files'] for k in f.get('unchangedProposalStates',[])}
for s in selected:
    name=f"{s['device'].replace(' ','-')}-{s['theme']}-{s['state']}.png"
    target=proofs/name
    if s['key'] in unchanged and target.exists():
        results.append({'key':s['key'],'file':s['file'],'page':'Discover Proposal','id':s['id'],'proof':str(target.relative_to(base)),'passed':True,'bytes':target.stat().st_size,'mode':'Reused prior strict raster: saved SVG exactly unchanged'})
        continue
    result=subprocess.run([str(cli),'export',str(base/'../Gus'/s['file']),'--node',s['id'],'--font-policy','strict','-o',str(target)],capture_output=True,text=True,timeout=60)
    if result.returncode:raise RuntimeError(result.stderr)
    results.append({'key':s['key'],'file':s['file'],'page':'Discover Proposal','id':s['id'],'proof':str(target.relative_to(base)),'passed':True,'bytes':target.stat().st_size})
    print(f"Raster {len(results)}/{len(selected)} PASS: {s['key']}",flush=True)
assert len(results)==len(manifest)
(qa/'strict-raster.json').write_text(json.dumps(results,indent=2))
