"""Build the shared app preview and indexes for current and proposed designs."""
import csv
import json
import re
from pathlib import Path
from urllib.parse import quote

p=Path(__file__).resolve().parent.parent
design=p.parent
preview=design/'Exports/Preview'
m=json.loads((p/'Source/screen-manifest.json').read_text())
parts=json.loads((p/'../Gus/index.json').read_text())
proposal_count=sum(s.get('scope')=='proposal' for s in m)
valid_keys={s['key'] for s in m}
for old in (preview/'preview-scenes').glob('*.js'):
    if old.stem not in valid_keys:old.unlink()
file_by_key={key:row['file'] for row in parts['files'] for key in row['keys']+row.get('proposalKeys',[])}
for s in m:
    s.setdefault('scope','current')
    s['file']=file_by_key[s['key']]
    s['page']='Discover Proposal' if s['scope']=='proposal' else 'App Screens'
head=(preview/'Preview.html').read_text().split('<script>')[0]
if 'rel="icon"' not in head:head=head.replace('</head>','<link rel="icon" href="data:,"></head>')
head=head.replace('Specifications/Discover.md','../../DISCOVER.md')
head=head.replace('<p>Source-based design preview</p>','<p>Current app and proposed feature designs</p>')
if 'id="scope"' not in head:
    head=head.replace('<label>Layout', '<label>Designs<select aria-label="Designs" id="scope"><option value="current">Current app</option><option value="proposal">Discover proposal</option></select></label><p id="scope-note" class="hint"></p><p><a id="design-file">Open editable design</a></p><p><a href="../../DISCOVER.md">Discover specification</a></p><label>Layout')
head=re.sub(r'(?:All 2,896 inventory scenes|2,896 current-app scenes and [0-9]+ Discover proposal scenes) are available\.',f'2,896 current-app scenes and {proposal_count} Discover proposal scenes are available.',head)
index=[{k:s[k] for k in ['key','device','theme','spec','title','w','h','scope','file','page']} for s in m]
engine=(p/'Source/preview-engine.js').read_text().replace('GUS_SCREEN_INDEX',json.dumps(index))
(preview/'Preview.html').write_text(head+'<script>'+engine.replace('</script','<\\/script')+'</script></body></html>')
keys={(s['scope'],s['device'],s['theme'],s['spec']) for s in m}
missing=[]
unrepresented=[]
edges=regions=0
with (p/'navigation.csv').open('w') as f:
    w=csv.writer(f,lineterminator='\n')
    w.writerow(['Layout','Appearance','From state','Target state','Target artboard available','Design status','Target design status'])
    for s in m:
        regions+=len(s.get('scrollRegions',[]))
        for link in s.get('links',[]):
            target=link['target'];kind=s['scope']
            if kind=='proposal':
                root={'gus-home':'home','gus-libraries':'libraries','gus-more':'more'}.get(target)
                if root:target=root;kind='current'
                elif s['device']=='tvOS' and target=='movie':target='detail'
                elif s['device']=='visionOS' and target=='show':target='detail'
            available=(kind,s['device'],s['theme'],target) in keys
            edges+=1
            w.writerow([s['device'],s['theme'],s['spec'],link['target'],available,s['scope'],kind])
            if not available:
                (unrepresented if s['scope']=='proposal' else missing).append({'key':s['key'],'target':link['target']})
report={'scenes':len(m),'currentScenes':sum(s['scope']=='current' for s in m),'proposalScenes':sum(s['scope']=='proposal' for s in m),'navigationEdges':edges,'unavailableCurrentTargets':missing,'unrepresentedProposalActions':unrepresented,'scrollRegions':regions,'proposalScrolling':'Static viewports; not a scroll simulation','browserAcceptance':'See QA/Discover/browser-acceptance.json for targeted proposal checks; current-app prior acceptance remains separate.'}
(p/'QA/navigation-audit.json').write_text(json.dumps(report,indent=2))
with (p/'coverage.csv').open() as f:
    existing=list(csv.DictReader(f))
rows=[r for r in existing if r.get('Design status','current')=='current']
by_state={(s['device'],s['theme'],s['spec']):s for s in m if s['scope']=='current'}
for r in rows:
    s=by_state[(r['Layout'],r['Appearance'],r['State'])]
    r.update({'Design status':'current','Editable file':'Gus/'+s['file'],'Page':'App Screens'})
for s in json.loads((p/'Source/discover/manifest.json').read_text()):
    rows.append({'Layout':s['device'],'Appearance':s['theme'],'State':s['state'],'Screen':s['title'],'Source':'DISCOVER.md','Editable layers':s['layers'],'Evidence':'Proposed feature design; not implemented. See References/QA/Discover/integration.json.','Design status':'proposal','Editable file':'Gus/'+s['file'],'Page':'Discover Proposal'})
with (p/'coverage.csv').open('w') as f:
    w=csv.DictWriter(f,fieldnames=['Layout','Appearance','State','Screen','Source','Editable layers','Evidence','Design status','Editable file','Page'],lineterminator='\n')
    w.writeheader();w.writerows(rows)
lines=['# Gus OpenPencil files','',f"{len(parts['files'])} standalone files · {len(m):,} artboards: 2,896 current-app references plus {proposal_count} proposed Discover designs.",'',
       'Use [the shared preview](Exports/Preview/Preview.html) for the current app, or [Discover proposal mode](Exports/Preview/Preview.html#discover-proposal) for Seerr. The [Discover specification](DISCOVER.md) defines the proposed behavior.', '',
       'Every file has App Screens, Guide & Coverage and Components. The ten Discover files listed with a proposal count also have **Discover Proposal**. Their proposal resources are grouped inside the existing Components and Guide & Coverage pages. No separate Seerr master or review document is required.', '',
       'Current-app references and proposed behavior remain explicitly labeled. Light/dark and device coverage varies by proposal; blank variants have not been invented. Watch remains unchanged. See [README](README.md) for validation and native-editor limitations.','',
       '| Layout | Appearance | Area | Current | Proposed | Size |','|---|---|---|---:|---:|---:|']
for r in parts['files']:
    size=(p/'../Gus'/r['file']).stat().st_size
    lines.append(f"| {r['device']} | {r['theme']} | [{r['area']}](Gus/{quote(r['file'])}) | {r['artboards']} | {r.get('proposalArtboards',0)} | {size//1024:,} KB |")
(design/'SCREEN-COVERAGE.md').write_text('\n'.join(lines)+'\n')
print(json.dumps({k:v for k,v in report.items() if not isinstance(v,list)}))
if missing:raise SystemExit('Current-app navigation has unavailable targets')
