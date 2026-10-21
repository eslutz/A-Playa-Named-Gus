import {sdkRoot} from '../sdk.mjs';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const core=await import(sdkRoot+'/core/dist/index.js');
const manifest=JSON.parse(fs.readFileSync(path.join(base,'Source/discover/manifest.json'))),groups=new Map();
for(const s of manifest){if(!groups.has(s.file))groups.set(s.file,[]);groups.get(s.file).push(s);}
const results=[];
for(const [file,scenes]of groups){
 const b=fs.readFileSync(path.join(base,'../Gus',file)),g=await core.parseFigFile(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),{populate:'all'}),ns=[...g.getAllNodes()],page=g.getPages().find(p=>p.name==='Discover Proposal');
 const descendants=id=>g.getChildren(id).flatMap(n=>[n,...descendants(n.id)]);
 const proposalIds=new Set(page?descendants(page.id).map(n=>n.id):[]);
 const expected=new Set(scenes.map(s=>s.name)),boards=page?g.getChildren(page.id):[],styleIds=new Set(ns.filter(n=>n.sharedStyleType).flatMap(n=>[n.id,n.source.id]));
 const result={file,artboards:boards.length,expected:scenes.length,missing:scenes.filter(s=>!boards.some(n=>n.name===s.name)).map(s=>s.name),extra:boards.filter(n=>!expected.has(n.name)).map(n=>n.name),brokenInstances:ns.filter(n=>n.type==='INSTANCE'&&!g.getNode(n.componentId)).length,brokenStyles:ns.filter(n=>n.textStyleId&&!styleIds.has(n.textStyleId)).length,invalidGeometry:ns.filter(n=>['x','y','width','height'].some(k=>!Number.isFinite(n[k]))||proposalIds.has(n.id)&&n.type==='TEXT'&&n.width<1).length};
 if(result.missing.length||result.extra.length||result.brokenInstances||result.brokenStyles||result.invalidGeometry)throw Error(JSON.stringify(result));
 for(const s of scenes){const n=boards.find(n=>n.name===s.name);s.id=n.id;s.pageId=page.id;}
 results.push(result);
}
const contract=JSON.parse(fs.readFileSync(path.join(base,'Source/discover/coverage-contract.json')));
const required=[...contract.phoneAppearances.flatMap(theme=>contract.phoneStates.map(state=>({device:'iPhone',theme,state}))),...contract.adaptive.flatMap(row=>row.states.map(state=>({...row,state})))];
const missing=required.filter(r=>!manifest.some(s=>s.device===r.device&&s.theme===r.theme&&s.state===r.state));
if(missing.length||manifest.length!==required.length||new Set(manifest.map(s=>s.key)).size!==required.length)throw Error('Coverage contract failed '+JSON.stringify(missing));
fs.writeFileSync(path.join(base,'Source/discover/manifest.json'),JSON.stringify(manifest,null,2));
fs.writeFileSync(path.join(base,'QA/Discover/saved-readback.json'),JSON.stringify({artboards:manifest.length,files:results.length,checks:results},null,2));
console.log('PASS: '+manifest.length+' proposal artboards in '+results.length+' existing Discover files; references and geometry valid.');
