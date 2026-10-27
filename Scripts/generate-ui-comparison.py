#!/usr/bin/env python3
"""Generate a local, self-contained before/after UI report outside the source tree.

Image filenames identify scenarios. Optional references JSON maps scenario names to
{name, file}; file paths are relative to that JSON. Never writes captured evidence
into this repository.
"""
import argparse
import hashlib
import html
import json
import re
from pathlib import Path
import shutil
import struct


def image_info(path):
    data = path.read_bytes()
    size = struct.unpack('>II', data[16:24]) if data.startswith(b'\x89PNG\r\n\x1a\n') else None
    return {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data), 'pixels': size}


def append_iteration(output, captures, notes, findings_path=None):
    """Keep the historical HTML and manifest fields, appending only iteration two."""
    manifest_path = output / 'manifest.json'
    page_path = output / 'index.html'
    manifest = json.loads(manifest_path.read_text())
    page = page_path.read_text()
    historical_count = manifest.get('nextIteration', {}).get('historicalScenarioCount', len(manifest['scenarios']))
    originals = {row['scenario']: row for row in manifest['scenarios']}
    images = {p.stem: p for p in captures.glob('*.png')}
    for name in sorted(images.keys() - originals.keys()):
        row = {'scenario': name, 'before': None, 'after': None, 'reference': None, 'notes': ''}
        manifest['scenarios'].append(row)
        originals[name] = row
        title = html.escape(name.replace('-', ' ').title())
        missing = ''.join(f'<figure class="missing"><figcaption>{label}</figcaption><p>Not captured in this iteration</p></figure>' for label in ['Before', 'After'])
        section = f'<section id="{html.escape(name)}" data-name="{html.escape(name)}" data-paired="false"><h2>{title}</h2><p>Added in iteration 2; historical screenshots are unavailable.</p><div class="pair">{missing}</div></section>'
        page = page.replace('</main>', section + '</main>')
    for name, row in originals.items():
        source = images.get(name)
        if source:
            destination = output / 'iteration2' / source.name
            destination.parent.mkdir(exist_ok=True)
            if source.resolve() != destination.resolve():
                shutil.copy2(source, destination)
            relative = destination.relative_to(output).as_posix()
            row['nextIteration'] = {'file': relative, **image_info(destination)}
            figure = f'<figure class="iteration2"><figcaption>Iteration 2</figcaption><a href="{html.escape(relative)}"><img loading="lazy" src="{html.escape(relative)}" alt="{html.escape(name)} iteration 2"></a></figure>'
        else:
            figure = '<figure class="iteration2 missing"><figcaption>Iteration 2</figcaption><p>Capture unavailable</p></figure>'
        pattern = r'(<section id="' + re.escape(html.escape(name)) + r'".*?<div class="pair">)(.*?)(</div></section>)'
        def insert(match):
            historical = re.sub(r'<figure class="iteration2(?: missing)?">.*?</figure>', '', match.group(2), flags=re.S)
            return match.group(1) + historical + figure + match.group(3)
        page, count = re.subn(pattern, insert, page, count=1, flags=re.S)
        if count != 1:
            raise ValueError(f'Could not locate original report section: {name}')
    style = '<style id="iteration2-style">.pair{grid-template-columns:repeat(3,minmax(220px,1fr));overflow-x:auto}.iteration2 figcaption{color:#4f7c82}section{scroll-margin-top:220px}#iteration2-notes li{margin:10px 0}</style>'
    if 'id="iteration2-style"' not in page:
        page = page.replace('</style>', '</style>' + style, 1)
    count = sum(bool(row.get('nextIteration')) for row in manifest['scenarios'])
    detail = notes.read_text() if notes else ''
    findings = json.loads(findings_path.read_text()) if findings_path else []
    checklist = '<ol>' if findings else ''
    for finding in findings:
        links = ' · '.join(f'<a href="#{html.escape(name)}">{html.escape(name.replace("-", " "))}</a>' for name in finding.get('scenarios', []) if name in originals)
        checklist += f'<li value="{int(finding["number"])}"><strong>{html.escape(finding["title"])}</strong> — {html.escape(finding["detail"])}. {links}</li>'
    if findings:
        checklist += '</ol>'
        checklist = '<details><summary>Review checklist · ' + str(len(findings)) + ' findings</summary>' + checklist + '</details>'
    added = len(manifest['scenarios']) - historical_count
    aside = '<aside id="iteration2-notes"><h2>Iteration 2 · review fixes</h2><p>' + str(count) + ' third screenshots. Original Before/After images and notes are preserved. The original pair counts above describe the original ' + str(historical_count) + ' scenarios; ' + str(added) + ' new scenarios have no historical captures.</p><p>' + html.escape(detail).replace('\n', '<br>') + '</p>' + checklist + '</aside>'
    page = re.sub(r'<aside id="iteration2-notes">.*?</aside>', '', page, flags=re.S)
    page = page.replace('<main>', aside + '<main>', 1)
    manifest['nextIteration'] = {'label': 'Iteration 2', 'captures': count, 'historicalScenarioCount': historical_count, 'notes': detail, 'findings': findings}
    page_path.write_text(page)
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'report': str(page_path), 'thirdScreenshots': count, 'historicalScenarios': historical_count}))


def append_follow_up(output, captures, notes):
    """Add focused follow-up captures without changing any historical columns."""
    manifest_path = output / 'manifest.json'
    page_path = output / 'index.html'
    manifest = json.loads(manifest_path.read_text())
    page = page_path.read_text()
    rows = {row['scenario']: row for row in manifest['scenarios']}
    images = sorted(captures.glob('*.png'))
    if not images or any(image.stem not in rows for image in images):
        raise ValueError('Follow-up captures must match existing report scenarios.')
    for source in images:
        name = source.stem
        destination = output / 'followup' / source.name
        destination.parent.mkdir(exist_ok=True)
        shutil.copy2(source, destination)
        relative = destination.relative_to(output).as_posix()
        rows[name]['followUp'] = {'file': relative, **image_info(destination)}
        figure = f'<figure class="followup"><figcaption>Review follow-up</figcaption><a href="{html.escape(relative)}"><img loading="lazy" src="{html.escape(relative)}" alt="{html.escape(name)} review follow-up"></a></figure>'
        pattern = r'(<section id="' + re.escape(html.escape(name)) + r'".*?<div class="pair">)(.*?)(</div></section>)'
        def insert(match):
            historical = re.sub(r'<figure class="followup">.*?</figure>', '', match.group(2), flags=re.S)
            return match.group(1) + historical + figure + match.group(3)
        page, count = re.subn(pattern, insert, page, count=1, flags=re.S)
        if count != 1:
            raise ValueError(f'Could not locate report section: {name}')
    style = '<style id="followup-style">.pair:has(.followup){grid-template-columns:repeat(4,minmax(220px,1fr))}.followup figcaption{color:#4f7c82}</style>'
    if 'id="followup-style"' not in page:
        page = page.replace('</head>', style + '</head>', 1)
    detail = notes.read_text() if notes else ''
    links = ' · '.join(f'<a href="#{html.escape(image.stem)}">{html.escape(image.stem.replace("-", " "))}</a>' for image in images)
    aside = '<aside id="followup-notes"><h2>Review follow-up</h2><p>' + html.escape(detail).replace('\n', '<br>') + '</p><p>' + links + '</p></aside>'
    page = re.sub(r'<aside id="followup-notes">.*?</aside>', '', page, flags=re.S)
    page = page.replace('<main>', aside + '<main>', 1)
    manifest['followUp'] = {'captures': len(images), 'notes': detail}
    page_path.write_text(page)
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'report': str(page_path), 'followUpScreenshots': len(images)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path)
    parser.add_argument('--after', type=Path)
    parser.add_argument('--next-iteration', type=Path, help='Append third images to an existing report; preserve its history')
    parser.add_argument('--follow-up', type=Path, help='Append focused fourth images; preserve the first three columns')
    parser.add_argument('--references', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--notes', type=Path, help='Plain-text scope, validation and limitations for the report')
    parser.add_argument('--findings', type=Path, help='Iteration checklist JSON stored outside source')
    parser.add_argument('--baseline', default='Unspecified')
    parser.add_argument('--device')
    args = parser.parse_args()
    output = args.output.resolve()
    repo = Path(__file__).resolve().parent.parent
    if output == repo or repo in output.parents:
        parser.error('Comparison reports and captures must be written outside the source repository.')
    if args.follow_up:
        if args.next_iteration or not args.follow_up.is_dir() or not (output / 'manifest.json').is_file():
            parser.error('Follow-up requires an existing report and capture directory, without --next-iteration.')
        append_follow_up(output, args.follow_up, args.notes)
        return
    if args.next_iteration:
        if not args.next_iteration.is_dir() or not (output / 'manifest.json').is_file() or not (output / 'index.html').is_file():
            parser.error('Appending requires a capture directory and an existing report with a manifest.')
        append_iteration(output, args.next_iteration, args.notes, args.findings)
        return
    if not args.before or not args.after or not args.device:
        parser.error('Creating a report requires --before, --after and --device.')
    for folder in [args.before, args.after]:
        if not folder.is_dir():
            parser.error(f'Capture directory does not exist: {folder}')
    output.mkdir(parents=True, exist_ok=True)
    references = json.loads(args.references.read_text()) if args.references else {}
    before = {p.stem: p for p in args.before.glob('*.png')}
    after = {p.stem: p for p in args.after.glob('*.png')}
    rows = []
    manifest = []
    for name in sorted(before.keys() | after.keys()):
        record = {'scenario': name, 'before': None, 'after': None, 'reference': None}
        figures = []
        for label, images in [('Before', before), ('After', after)]:
            source = images.get(name)
            if source:
                destination = output / label.lower() / source.name
                destination.parent.mkdir(exist_ok=True)
                if destination.resolve() != source.resolve():
                    shutil.copy2(source, destination)
                relative = destination.relative_to(output).as_posix()
                record[label.lower()] = {'file': relative, **image_info(destination)}
                figures.append(f'<figure><figcaption>{label}</figcaption><a href="{html.escape(relative)}"><img loading="lazy" src="{html.escape(relative)}" alt="{html.escape(name)} {label.lower()}"></a></figure>')
            else:
                figures.append(f'<figure class="missing"><figcaption>{label}</figcaption><p>Capture unavailable</p></figure>')
        ref = references.get(name)
        if ref and args.references and ref.get('file'):
            source = args.references.parent / ref['file']
            if source.is_file():
                destination = output / 'references' / source.name
                destination.parent.mkdir(exist_ok=True)
                if destination.resolve() != source.resolve():
                    shutil.copy2(source, destination)
                relative = destination.relative_to(output).as_posix()
                record['reference'] = {'name': ref['name'], 'file': relative, **image_info(destination)}
        record['notes'] = ref.get('note', '') if ref else ''
        paired = bool(record['before'] and record['after'])
        reference = record['reference']
        note = f'<a href="{html.escape(reference["file"])}">Sketch: {html.escape(reference["name"])}</a>' if reference else 'No explicit Sketch reference mapped; review shared styling and retained behavior.'
        if not paired:
            note += ' — Incomplete pair; this entry does not establish a completed comparison.'
        detail = ref.get('note', '') if ref else ''
        if detail:
            note += '<br>' + html.escape(detail)
        rows.append(f'<section id="{html.escape(name)}" data-name="{html.escape(name)}" data-paired="{str(paired).lower()}"><h2>{html.escape(name.replace("-", " ").title())}</h2><p>{note}</p><div class="pair">{"".join(figures)}</div></section>')
        manifest.append(record)
    paired = sum(bool(r['before'] and r['after']) for r in manifest)
    title = 'Gus iPhone · Sketch implementation'
    notes = '<aside>' + html.escape(args.notes.read_text()).replace('\n', '<br>') + '</aside>' if args.notes else ''
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>''' + title + '''</title><style>
:root{color-scheme:light;font:16px system-ui;color:#162e33;background:#f4f6f8}body{max-width:1140px;margin:auto;padding:24px}header{position:sticky;top:0;background:#f4f6f8f5;padding:12px 0;z-index:1}h1{font-size:28px;margin:0}p{line-height:1.5}input{padding:12px;border:1px solid #ccd4dc;border-radius:10px;width:min(75%,500px)}a{color:#0060c9}section{background:white;padding:24px;border-radius:18px;margin:24px 0}h2{margin-top:0}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px}figure{margin:0;text-align:center}figcaption{font-weight:650;margin-bottom:12px}img{width:100%;max-width:360px;height:auto;border:1px solid #dde2e7;border-radius:14px}.missing{background:#fff4e7;min-height:180px}[hidden]{display:none!important}@media(max-width:600px){body{padding:10px}section{padding:14px}.pair{gap:8px}}
</style><header><h1>''' + title + '''</h1><p>Light mode · ''' + html.escape(args.device) + '<br>Baseline: ' + html.escape(args.baseline) + f'<br>{paired} paired scenarios · {len(manifest) - paired} incomplete pairs. Open an image for its original resolution.</p>' + '''<input id="filter" type="search" placeholder="Find a screen or state" aria-label="Filter comparisons"><label><input id="incomplete" type="checkbox" style="width:auto"> Show incomplete pairs only</label></header>''' + notes + '''<main>''' + '\n'.join(rows) + '''</main><script>
const filter=document.querySelector('#filter'),incomplete=document.querySelector('#incomplete');function update(){document.querySelectorAll('section').forEach(section=>section.hidden=!section.dataset.name.includes(filter.value.toLowerCase().replaceAll(' ','-'))||(incomplete.checked&&section.dataset.paired==='true'))}filter.addEventListener('input',update);incomplete.addEventListener('change',update);
</script></html>'''
    (output / 'index.html').write_text(page)
    (output / 'manifest.json').write_text(json.dumps({'device': args.device, 'baseline': args.baseline, 'paired': paired, 'scenarios': manifest}, indent=2) + '\n')
    print(json.dumps({'report': str(output / 'index.html'), 'paired': paired, 'incomplete': len(manifest) - paired}))


if __name__ == '__main__':
    main()
