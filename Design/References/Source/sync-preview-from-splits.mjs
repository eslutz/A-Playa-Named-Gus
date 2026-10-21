import fs from 'node:fs';import path from 'node:path';
import {createRequire} from 'node:module';import {pathToFileURL} from 'node:url';
const base=path.resolve('Design/References'),index=JSON.parse(fs.readFileSync(base+'/../Gus/index.json'));
const require=createRequire((process.env.GUS_OPENPENCIL_CLI_ROOT||'/private/tmp/gus-openpencil-cli')+'/package.json');
const core=await import(pathToFileURL(require.resolve('@open-pencil/core')).href);
const manifest=JSON.parse(fs.readFileSync(base+'/Source/screen-manifest.json')),byKey=new Map(manifest.map(m=>[m.key,m]));
const only=new Set((process.env.GUS_SYNC_FILES||'').split(',').filter(Boolean).map(Number));
for(const [i,row]of index.files.entries()){
 if(only.size&&!only.has(i))continue;
 const file=base+'/../Gus/'+row.file,b=fs.readFileSync(file),g=await core.parseFigFile(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),{populate:'all'}),page=g.getPages().find(p=>p.name==='App Screens'),walk=id=>g.getChildren(id).flatMap(n=>[n,...walk(n.id)]);
 row.bytes=b.length;
 for(const key of row.keys){const m=byKey.get(key),root=g.getChildren(page.id).find(n=>n.name===`${m.device} / ${m.theme} / ${m.spec} — ${m.title}`),origin=g.getAbsolutePosition(root.id),ns=walk(root.id);
  m.links=ns.filter(n=>n.name.startsWith('[go:')).map(n=>{const a=g.getAbsolutePosition(n.id);return{target:n.name.match(/^\[go:([^\]]+)\]/)[1],x:a.x-origin.x,y:a.y-origin.y,w:n.width,h:n.height,nodeId:n.id};});
  m.scrollRegions=ns.filter(n=>n.clipsContent&&/viewport|rail|List|Scrollable|Watch List/i.test(n.name)).map(n=>{const a=g.getAbsolutePosition(n.id),children=walk(n.id).filter(c=>c.visible);return{id:n.id,name:n.name,x:a.x-origin.x,y:a.y-origin.y,w:n.width,h:n.height,maxX:/rail/i.test(n.name)?Math.max(0,...children.map(c=>{const b=g.getAbsolutePosition(c.id);return b.x-a.x+c.width-n.width;})):0,maxY:/rail/i.test(n.name)?0:Math.max(0,...children.map(c=>{const b=g.getAbsolutePosition(c.id);return b.y-a.y+c.height-n.height;}))};}).filter(r=>r.maxX>2||r.maxY>2);
  for(const l of m.links){const parents=[];let n=g.getNode(l.nodeId);while(n?.parentId){parents.push(n.parentId);n=g.getNode(n.parentId);}l.regions=m.scrollRegions.filter(r=>parents.includes(r.id)).map(r=>r.id);}
  const svg=core.renderNodesToSVG(g,page.id,[root.id]);fs.writeFileSync(base+'/../Exports/Preview/preview-scenes/'+key+'.js','window.GusPreview.register('+JSON.stringify({...m,svg})+');');
 }
 console.log(row.file);
}
fs.writeFileSync(base+'/../Gus/index.json',JSON.stringify(index,null,2));fs.writeFileSync(base+'/Source/screen-manifest.json',JSON.stringify(manifest,null,2));
