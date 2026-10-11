import json,pathlib,subprocess,shutil,time,zipfile
sim='7889A486-07F4-4BE9-B92A-903BA2C1A1E9'
container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',sim,'dev.ericslutz.gus','data'],text=True).strip())
d=json.load(open('/tmp/gus-device-repair/demo-fixture.json'));server=d['server'];user=d['user']
root=container/'Library/Application Support/A Playa Named Gus/Downloads';folder=root/server/user;folder.mkdir(parents=True,exist_ok=True)
f=root/'records.json';records=json.loads(f.read_text());assert all(r['serverID']==server and r['userID']==user for r in records)
epub=pathlib.Path('/tmp/gus-device-repair/completion.epub')
with zipfile.ZipFile(epub,'w') as z:
 z.writestr('mimetype','application/epub+zip',compress_type=zipfile.ZIP_STORED)
 z.writestr('META-INF/container.xml','<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
 z.writestr('book.opf','''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">gus-test-epub</dc:identifier><dc:title>Completion Fixture</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-10-11T12:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="start" href="start.xhtml" media-type="application/xhtml+xml"/><item id="end" href="end.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="start"/><itemref idref="end"/></spine></package>''')
 z.writestr('nav.xhtml','''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="start.xhtml">Beginning</a></li><li><a href="end.xhtml">Final Chapter</a></li></ol></nav></body></html>''')
 for part,title in [('start','Beginning'),('end','Final Chapter')]:z.writestr(part+'.xhtml',f'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title></head><body><h1>{title}</h1><p>This is an original disposable fixture for download completion verification.</p></body></html>')
audio=next(pathlib.Path('sample_media').rglob('*.mp3'));out=pathlib.Path('/tmp/gus-device-repair/repeat.mp3')
subprocess.run(['ffmpeg','-y','-i',str(audio),'-t','8','-c:a','libmp3lame',str(out)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
for key,name,typ,src,ext in [('epub-final','Finish EPUB','Book',epub,'epub'),('repeat-final','Repeat Audio','Audio',out,'mp3')]:
 id='gus-fixture-'+key;records=[r for r in records if r['item'].get('Id')!=id];dest=folder/(id+'.'+ext);shutil.copy2(src,dest)
 records.append({'id':f'{server}:{user}:{id}','item':{'Id':id,'Name':name,'Type':typ,'CanDownload':True,'RunTimeTicks':80000000},'filePath':str(dest),'byteCount':dest.stat().st_size,'serverID':server,'userID':user,'downloadedAt':time.time()-978307200,'status':{'kind':'complete'},'progress':1})
f.write_text(json.dumps(records));print('Seeded EPUB and repeat-audio disposable fixtures')
