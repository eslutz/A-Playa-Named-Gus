from pathlib import Path
import time,json,subprocess,importlib.util
app=Path('/Users/ericslutz/Developer/Code/Side Projects/A Playa Named Gus/Gus')
root=Path('/tmp/gus-staged-candidate');base=Path('/tmp/gus-final-validation-10')
deadline=time.monotonic()+2400
while time.monotonic()<deadline:
    p=base/'phases.json'
    if p.exists():

        try:phases=json.loads(p.read_text())
        except json.JSONDecodeError:
            time.sleep(.1);continue
        if any(r['exitCode'] for r in phases):raise SystemExit('Core failed; do not change a still-running candidate')
        if len(phases)==5:break
    time.sleep(1)
else:raise SystemExit('Core completion timeout; launch helper unchanged')
p=app/'Scripts/measure-launch-baseline.sh';s=p.read_text()
assert 'Debug-iphonesimulator/Gus.app' in s
p.write_text(s.replace('Debug-iphonesimulator/Gus.app','Debug-iphonesimulator/A Playa Named Gus.app'))
subprocess.run(['zsh','-n',str(p)],check=True)
subprocess.run(['git','add','--','Scripts/measure-launch-baseline.sh'],cwd=app,check=True)
subprocess.run(['git','checkout-index','--prefix=/tmp/gus-staged-candidate/','-f','--','Scripts/measure-launch-baseline.sh'],cwd=app,check=True)
spec=importlib.util.spec_from_file_location('v',root/'Scripts/validate-release.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
old=json.loads((base/'archives/source-hashes.json').read_text());new=v.source_hashes(root)
changed=sorted(k for k in set(old)|set(new) if old.get(k)!=new.get(k))
assert changed==['Scripts/measure-launch-baseline.sh'],changed
(base/'launch-tooling-provenance.json').write_text(json.dumps({'postCoreChangedInputs':changed,'shippingSourceConfigDependenciesAndTestsUnchanged':True,'reason':'The observed product name corrects only the launch helper default path. Per-phase manifests are retained; fresh static checks and actual five-run helper execution validate this change.'},indent=2)+'\n')
subprocess.run(['python3','Scripts/validate-release.py','--phase','static','--root',str(root),'--output',str(base/'static-launch-correction')],cwd=root,check=True)
print('Launch path corrected after the frozen core phases; static recheck passed.',flush=True)
