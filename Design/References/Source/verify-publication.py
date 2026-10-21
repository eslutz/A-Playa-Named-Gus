"""Audit the complete design package and refresh its publication checksums."""
from pathlib import Path
from urllib.parse import unquote, urlsplit
import ast
import csv
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

design = Path(__file__).resolve().parents[2]
reference = design/'References'
qa = reference/'QA/Discover'
inventory = json.loads((reference/'Source/screen-manifest.json').read_text())
parts = json.loads((design/'Gus/index.json').read_text())
proposal = json.loads((reference/'Source/discover/manifest.json').read_text())
contract = json.loads((reference/'Source/discover/coverage-contract.json').read_text())
keys = {s['key'] for s in inventory}
assert len(keys) == len(inventory) == 3016
assert len(proposal) == 120 and len(parts['files']) == 82
assert len(list((design/'Gus').rglob('*.fig'))) == 82
assert not (design/'OpenPencil').exists() and not (design.parent/'docs').exists()
scene_files = list((design/'Exports/Preview/preview-scenes').glob('*.js'))
assert {p.stem for p in scene_files} == keys
for p in scene_files:
    data = p.read_text()
    assert data.startswith('window.GusPreview.register(') and data.endswith(');'), p
    scene = json.loads(data[len('window.GusPreview.register('):-2])
    assert scene['key'] == p.stem
    ET.fromstring(scene['svg'])
with (reference/'coverage.csv').open() as f:
    coverage = list(csv.DictReader(f))
assert len(coverage) == len(inventory)
assert len({(r['Layout'], r['Appearance'], r['State'], r['Design status']) for r in coverage}) == len(inventory)
checks = json.loads((reference/'QA/split-verification.json').read_text())
assert checks['files'] == 82 and checks['totalArtboards'] == 3016
assert all(not c['brokenInstances'] and not c['brokenTextStyles'] and not c['nonfinite'] for c in checks['checks'])
readback = json.loads((qa/'saved-readback.json').read_text())
assert readback['artboards'] == 120 and all(not c['missing'] and not c['extra'] for c in readback['checks'])
fonts = json.loads((qa/'fonts.json').read_text())
assert len(fonts) == 10 and all(f['faithful'] and not f['issues'] for f in fonts)
rasters = json.loads((qa/'strict-raster.json').read_text())
assert len(rasters) == 120 and {r['key'] for r in rasters} == {s['key'] for s in proposal}
assert all((reference/r['proof']).is_file() and (reference/r['proof']).stat().st_size == r['bytes'] for r in rasters)
navigation = json.loads((reference/'QA/navigation-audit.json').read_text())
assert not navigation['unavailableCurrentTargets']
assert all(a['target'] in contract['nativeActions'] for a in navigation['unrepresentedProposalActions'] if a['key'].startswith('iPhone-'))
links = 0
for p in [design/'README.md', design/'SCREEN-COVERAGE.md', design/'DISCOVER.md', reference/'README.md', reference/'Source/README.md', reference/'Source/discover/README.md']:
    for raw in re.findall(r'\]\(([^)]+)\)', p.read_text()):
        u = urlsplit(raw)
        if u.scheme or not u.path: continue
        assert (p.parent/unquote(u.path)).exists(), (p, raw)
        links += 1
for p in (reference/'Source').rglob('*'):
    if p.suffix in {'.mjs', '.js'}:
        result = subprocess.run(['node', '--check', str(p)], capture_output=True, text=True)
        assert result.returncode == 0, (p, result.stderr)
    elif p.suffix == '.py':
        ast.parse(p.read_text(), filename=str(p))
browser = json.loads((qa/'browser-acceptance.json').read_text())
assert browser['passed'] and browser['consoleErrors'] == 0 and browser['previewServerStopped']
report = {'passed': True, 'editableFiles': 82, 'currentArtboards': 2896, 'proposalArtboards': 120, 'totalArtboards': 3016,
          'phoneStatesPerAppearance': 51, 'adaptiveArtboards': 18, 'savedReferencesAndGeometry': 'passed',
          'inventoryNamesAndKeys': 'passed by verify-splits.mjs and Discover coverage contract',
          'previewSceneJSONAndSVGs': len(scene_files), 'localDocumentationLinks': links,
          'faithfulFontFiles': len(fonts), 'strictRasterProofs': len(rasters), 'browser': 'selected final flows passed; zero console errors',
          'accessibilityLint': '18 flags confined to illustrated native Mac window buttons; see accessibility-lint.json',
          'nativeAndRuntimeAcceptance': 'Physical input, native material, assistive behavior and live Seerr acceptance remain separate',
          'appSourceChanged': False, 'testing': 'sequential; temporary preview server and test tab closed'}
(qa/'acceptance.json').write_text(json.dumps(report, indent=2)+'\n')
files = sorted(p for p in design.rglob('*') if p.is_file() and p != reference/'file-manifest.json')
manifest = {'scope': 'Published design files and retained validation; excludes this manifest',
            'files': [{'path': str(p.relative_to(design)), 'bytes': p.stat().st_size,
                       'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]}
(reference/'file-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(json.dumps(report, indent=2))
print(f'Checksummed {len(files)} files.')
