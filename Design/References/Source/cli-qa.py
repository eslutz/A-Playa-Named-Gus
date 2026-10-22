"""Read-only CLI checks and one strict-font raster proof per standalone file."""
import collections, hashlib, json, os, pathlib, subprocess, time, tempfile
from types import SimpleNamespace

base = pathlib.Path(__file__).resolve().parent.parent
cli_root = pathlib.Path(os.environ.get('GUS_OPENPENCIL_CLI_ROOT', '/private/tmp/gus-openpencil-cli'))
command = ['node', '--import', str(base/'Source/cli-fonts.mjs'), str(cli_root/'node_modules/@open-pencil/cli/bin/openpencil.js')]
report_path=base/'QA'/os.environ.get('GUS_CLI_REPORT','cli-acceptance.json')
rows = json.loads((base/'../Gus/index.json').read_text())['files']
out = base/'QA/CLI'
out.mkdir(exist_ok=True)
only = {int(x) for x in os.environ.get('GUS_CLI_ONLY', '').split(',') if x}
report = {'cliVersion': '0.16.0', 'mode': 'headless file commands; no desktop connection', 'fontSource': 'installed static SF Pro Text and SF Compact Text via process-local preloader', 'automaticFixesApplied': False, 'passCriteria': 'Expected artboard count, faithful fonts, strict-font export and unchanged input checksum. Lint findings are tracked separately; passedFiles does not mean lint-clean.', 'files': []}

if only and report_path.exists():
    report=json.loads(report_path.read_text())
report['passCriteria']='Expected artboard count, faithful fonts, strict-font export and unchanged input checksum. Lint findings are tracked separately; passedFiles does not mean lint-clean.'

def call(args, allow_lint=False):
    # CLI lint exits immediately on errors; a regular file avoids truncated pipe output.
    with tempfile.TemporaryFile(mode='w+', encoding='utf-8') as output:
        completed = subprocess.run(command+args, stdout=output, stderr=subprocess.PIPE, text=True, timeout=60)
        output.seek(0)
        result = SimpleNamespace(returncode=completed.returncode, stdout=output.read(), stderr=completed.stderr)
    if result.returncode and not allow_lint:
        raise RuntimeError(result.stderr or result.stdout)
    return result

for i, row in enumerate(rows):
    if only and i not in only:
        continue
    file = base/'../Gus'/row['file']
    start = time.monotonic()
    before = hashlib.sha256(file.read_bytes()).hexdigest()
    tree = json.loads(call(['tree', str(file), '--page', 'App Screens', '--depth', '1', '--json']).stdout)
    fonts = json.loads(call(['fonts', str(file), '--json']).stdout)
    lint = json.loads(call(['lint', str(file), '--json'], allow_lint=True).stdout)
    rules = collections.Counter(m['ruleId'] for m in lint.get('messages', []))
    severity = collections.Counter(m['severity'] for m in lint.get('messages', []))
    samples = []
    for rule in rules:
        samples.extend([{k:m.get(k) for k in ['ruleId','severity','message','nodePath']} for m in lint['messages'] if m['ruleId']==rule][:2])
    first = tree[0]
    proof = out/f'{i+1:03d}.png'
    scale = min(1, 800/first['width'], 1000/first['height'])
    exported = call(['export', str(file), '--node', first['id'], '--format', 'png', '--font-policy', 'strict', '--scale', str(scale), '--output', str(proof)])
    after = hashlib.sha256(file.read_bytes()).hexdigest()
    result = {'file':row['file'], 'artboards':len(tree), 'expectedArtboards':row['artboards'], 'faithfulFonts':fonts['faithful'], 'faces':[{k:f.get(k) for k in ['family','style','status','source','substituteFamily']} for f in fonts['faces']], 'fontIssueCount':len(fonts['issues']), 'lintRules':dict(rules), 'lintSeverity':dict(severity), 'lintSamples':samples, 'renderedScreen':first['name'], 'proof':str(proof.relative_to(base)), 'strictFontExportPassed':True, 'sha256Before':before, 'sha256After':after, 'elapsedSeconds':round(time.monotonic()-start,2)}
    result['passed']=len(tree)==row['artboards'] and fonts['faithful'] and not fonts['issues'] and before==after
    report['files']=[r for r in report['files'] if r['file']!=row['file']]
    report['files'].append(result)
    order={r['file']:j for j,r in enumerate(rows)}
    report['files'].sort(key=lambda r:order[r['file']])
    report.update({'checkedFiles':len(report['files']), 'passedFiles':sum(r['passed'] for r in report['files']), 'checkedArtboards':sum(r['artboards'] for r in report['files'])})
    report_path.write_text(json.dumps(report,indent=2))
    print(f"{i+1}/82 {row['file']} passed={result['passed']}",flush=True)
    if not result['passed']:
        raise RuntimeError('CLI validation failed: '+row['file'])
