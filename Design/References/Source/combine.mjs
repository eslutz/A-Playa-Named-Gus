/** Combine the split documents through a headless OpenPencil CLI eval script. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {layoutLibrary} from './library-layout.mjs';
import {createRequire} from 'node:module';
import {fileURLToPath,pathToFileURL} from 'node:url';
const design=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const cli=process.env.GUS_OPENPENCIL_CLI_ROOT||'/private/tmp/gus-openpencil-cli';
const require=createRequire(path.join(cli,'package.json'));
const core=await import(pathToFileURL(require.resolve('@open-pencil/core')).href);
const {SceneGraph,prepareGraphTransfer,applyGraphTransfer}=await import(pathToFileURL(require.resolve('@open-pencil/scene-graph')).href);
const sha=v=>crypto.createHash('sha256').update(typeof v==='string'||ArrayBuffer.isView(v)?v:JSON.stringify(v)).digest('hex');
const metadataPath=file=>path.resolve(file)===path.join(design,'Gus.fig')?path.join(design,'References/combined-manifest.json'):file+'.manifest.json';
const walk=(g,id)=>[g.getNode(id),...g.getChildren(id).flatMap(n=>walk(g,n.id))];
async function read(file){const b=await fs.readFile(file);return core.parseFigFile(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),{populate:'all'});}
function normalized(v,ids=new Map()){
 if(typeof v==='string')return ids.get(v)||v;
 if(v===null||typeof v!=='object')return v;
 if(ArrayBuffer.isView(v))return Array.from(v);
 if(v instanceof Map)return [...v].map(([k,x])=>[ids.get(k)||k,normalized(x,ids)]).sort((a,b)=>String(a[0]).localeCompare(String(b[0])));
 if(Array.isArray(v))return v.map(x=>normalized(x,ids));
 return Object.fromEntries(Object.keys(v).sort().map(k=>[ids.get(k)||k,normalized(v[k],ids)]));
}
function rewrite(v,ids){
 if(typeof v==='string')return ids.get(v)||v;
 if(v===null||typeof v!=='object'||ArrayBuffer.isView(v))return v;
 if(v instanceof Map)return new Map([...v].map(([k,x])=>[ids.get(k)||k,rewrite(x,ids)]));
 if(Array.isArray(v)){const a=v.map(x=>rewrite(x,ids));return a.some((x,i)=>x!==v[i])?a:v;}
 let changed=false;const o={};for(const [k,x]of Object.entries(v)){const key=ids.get(k)||k,value=rewrite(x,ids);o[key]=value;changed||=key!==k||value!==x;}return changed?o:v;
}
function remapNodes(g,ids){
 if(!ids.size)return;
 for(const n of g.getAllNodes()){
  const props={};for(const [k,v]of Object.entries(n)){if(['id','parentId','childIds'].includes(k))continue;const next=rewrite(v,ids);if(next!==v)props[k]=next;}
  if(Object.keys(props).length)g.updateNode(n.id,props);
 }
}
function deduplicateVariables(g){
 const names=new Map();
 for(const c of g.variableCollections.values()){
  names.set(c.id,'collection:'+c.name);for(const m of c.modes)names.set(m.modeId,'mode:'+c.name+'/'+m.name);
 }
 for(const v of g.variables.values())names.set(v.id,'variable:'+g.variableCollections.get(v.collectionId)?.name+'/'+v.name);
 const groups=new Map(),ids=new Map(),removeVariables=[],removeCollections=[];
 for(const c of g.variableCollections.values()){
  const vars=[...g.variables.values()].filter(v=>v.collectionId===c.id).sort((a,b)=>a.name.localeCompare(b.name));
  const {id,...props}=c;
  const sig=sha(normalized({props,vars:vars.map(({id,...v})=>v),active:g.activeMode.get(c.id)},names));
  const old=groups.get(sig);
  if(!old){groups.set(sig,{c,vars});continue;}
  ids.set(c.id,old.c.id);removeCollections.push(c.id);
  for(let i=0;i<c.modes.length;i++)ids.set(c.modes[i].modeId,old.c.modes[i].modeId);
  for(let i=0;i<vars.length;i++){ids.set(vars[i].id,old.vars[i].id);removeVariables.push(vars[i].id);}
 }
 remapNodes(g,ids);
 for(const [id,v]of g.variables)if(!removeVariables.includes(id))g.variables.set(id,rewrite(v,ids));
 for(const [id,c]of g.variableCollections)if(!removeCollections.includes(id))g.variableCollections.set(id,rewrite(c,ids));
 for(const id of removeVariables)g.variables.delete(id);
 for(const id of removeCollections){g.variableCollections.delete(id);g.activeMode.delete(id);}
 return {variablesRemoved:removeVariables.length,collectionsRemoved:removeCollections.length};
}
function deduplicateStyles(g){
 const styles=[...g.getAllNodes()].filter(n=>n.sharedStyleType),names=new Map();
 for(const n of styles){const key='style:'+n.sharedStyleType+'/'+n.name;names.set(n.id,key);if(n.source.id)names.set(n.source.id,key);}
 const groups=new Map(),ids=new Map(),remove=[];
 for(const n of styles){const {id,parentId,childIds,source,x,y,...props}=n;const key=sha(normalized(props,names)),old=groups.get(key);if(!old){groups.set(key,n);continue;}ids.set(n.id,old.id);if(n.source.id)ids.set(n.source.id,old.source.id);remove.push(n.id);}
 remapNodes(g,ids);for(const id of remove)g.deleteNode(id);return {stylesRemoved:remove.length};
}
function deduplicateComponents(g){
 const roots=[...g.getAllNodes()].filter(n=>['COMPONENT','COMPONENT_SET'].includes(n.type)&&g.getNode(n.parentId)?.type!=='COMPONENT_SET');
 const properties=new Map();for(const n of g.getAllNodes())for(const d of n.componentPropertyDefinitions||[])properties.set(d.id,'property:'+d.name+'/'+d.type);
 const memo=new Map(),busy=new Set();
 function fingerprint(root){
  if(memo.has(root.id))return memo.get(root.id);if(busy.has(root.id))throw Error('Cyclic component '+root.name);busy.add(root.id);
  const local=new Map(properties);function paths(n,p){local.set(n.id,p);g.getChildren(n.id).forEach((c,i)=>paths(c,p+'/'+i));}paths(root,'self');
  function tree(n){const {id,parentId,childIds,source,...props}=n;let p=normalized(props,local);if(n.componentId&&!local.has(n.componentId)){const master=g.getNode(n.componentId);if(!master)throw Error('Missing component '+n.componentId);p.componentId='master:'+fingerprint(master);}return {props:p,children:g.getChildren(n.id).map(tree)};}
  const value=sha(tree(root));busy.delete(root.id);memo.set(root.id,value);return value;
 }
 const groups=new Map(),ids=new Map(),remove=[];
 for(const n of roots){const key=fingerprint(n),old=groups.get(key);if(!old){groups.set(key,n);continue;}
  const a=walk(g,n.id),b=walk(g,old.id);if(a.length!==b.length)throw Error('Inconsistent component fingerprint');
  for(let i=0;i<a.length;i++){ids.set(a[i].id,b[i].id);const ad=a[i].componentPropertyDefinitions||[],bd=b[i].componentPropertyDefinitions||[];for(let j=0;j<ad.length;j++)ids.set(ad[j].id,bd[j].id);}
  remove.push(n.id);
 }
 remapNodes(g,ids);for(const id of remove)if(g.getNode(id))g.deleteNode(id);return {componentTreesRemoved:remove.length};
}
function valid(g){
 const ns=[...g.getAllNodes()],styles=new Set(ns.filter(n=>n.sharedStyleType).flatMap(n=>[n.id,n.source.id]));
 const definitions=new Set(ns.flatMap(n=>(n.componentPropertyDefinitions||[]).map(p=>p.id)));
 const result={brokenInstances:ns.filter(n=>n.type==='INSTANCE'&&!g.getNode(n.componentId)).length,brokenStyles:ns.filter(n=>n.textStyleId&&!styles.has(n.textStyleId)).length,nonfinite:ns.filter(n=>['x','y','width','height'].some(k=>!Number.isFinite(n[k]))).length,brokenVariableBindings:0,brokenVariableAliases:0,brokenVariableCollections:0,brokenVariableModes:0,brokenComponentProperties:0};
 for(const n of ns){
  result.brokenVariableBindings+=Object.values(n.boundVariables||{}).filter(id=>!g.variables.has(id)).length;
  result.brokenComponentProperties+=(n.componentPropertyReferences||[]).filter(r=>!definitions.has(r.propertyId)).length;
  result.brokenComponentProperties+=Object.keys(n.componentPropertyValues||{}).filter(id=>!definitions.has(id)).length;
 }
 for(const v of g.variables.values()){
  const collection=g.variableCollections.get(v.collectionId);if(!collection){result.brokenVariableCollections++;continue;}
  const modes=new Set(collection.modes.map(m=>m.modeId));
  for(const [mode,value]of Object.entries(v.valuesByMode)){
   if(!modes.has(mode))result.brokenVariableModes++;
   if(value&&typeof value==='object'&&value.aliasId&&!g.variables.has(value.aliasId))result.brokenVariableAliases++;
  }
 }
 for(const c of g.variableCollections.values()){
  const modes=new Set(c.modes.map(m=>m.modeId));if(!modes.has(c.defaultModeId))result.brokenVariableModes++;
  if(g.activeMode.has(c.id)&&!modes.has(g.activeMode.get(c.id)))result.brokenVariableModes++;
  result.brokenVariableCollections+=c.variableIds.filter(id=>g.variables.get(id)?.collectionId!==c.id).length;
 }
 const library=g.getPages().find(p=>p.name==='Components');
 result.overlappingLibraryNodes=0;
 if(library){const children=g.getChildren(library.id);for(let i=0;i<children.length;i++)for(let j=i+1;j<children.length;j++){const a=children[i],b=children[j];if(a.x<b.x+b.width&&b.x<a.x+a.width&&a.y<b.y+b.height&&b.y<a.y+a.height)result.overlappingLibraryNodes++;}}
 if(Object.values(result).some(Boolean))throw Error(JSON.stringify(result));return result;
}
export async function combine({limit=0,output=path.join(design,'Gus.fig')}={}){
 const index=JSON.parse(await fs.readFile(path.join(design,'Gus/index.json'),'utf8'));
 const inventory=JSON.parse(await fs.readFile(path.join(design,'References/Source/screen-manifest.json'),'utf8'));
 const byKey=new Map(inventory.map(s=>[s.key,s]));
 const rows=limit?index.files.slice(0,limit):index.files;
 const g=new SceneGraph(),cover=g.getPages()[0];g.updateNode(cover.id,{name:'00 · Start Here'});
 const pages=new Map(),positions=new Map(),resourcePages=[],ledger=[],inputs=[];
 const pageFor=(scope,row)=>{const key=scope+'/'+row.device+'/'+row.theme;if(!pages.has(key)){const prefix=scope==='proposal'?'Proposal · ':'App · ';pages.set(key,g.addPage(prefix+row.device+' · '+row.theme));positions.set(key,64);}return {key,page:pages.get(key)};};
 // Create platform pages together, followed by all proposal pages.
 for(const row of rows)pageFor('current',row);
 for(const row of rows)if(row.proposalKeys?.length)pageFor('proposal',row);
 const beforeResources={};
 for(let ordinal=0;ordinal<rows.length;ordinal++){
  const row=rows[ordinal],file=path.join(design,'Gus',row.file),bytes=await fs.readFile(file);inputs.push({file:row.file,sha256:sha(bytes)});
  const source=await core.parseFigFile(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),{populate:'all'});
  const app=source.getPages().find(p=>p.name==='App Screens'),proposal=source.getPages().find(p=>p.name==='Discover Proposal');
  const entries=[...source.getChildren(app.id).map(n=>({n,scope:'current'})),...(proposal?source.getChildren(proposal.id).map(n=>({n,scope:'proposal'})):[])];
  const dep=source.getPages(true).filter(p=>p.id!==app.id&&p.id!==proposal?.id);
  const dest=pageFor('current',row).page;
  const plan=prepareGraphTransfer({source,rootIds:entries.map(x=>x.n.id),dependencyPageIds:dep.map(p=>p.id),target:g,parentId:dest.id});
  for(const n of plan.nodes)if(plan.dependencyPageIds.includes(n.id))n.props.internalOnly=true;
  applyGraphTransfer(g,plan);
  dep.forEach((p,i)=>resourcePages.push({id:plan.dependencyPageIds[i],kind:p.name}));
  for(const scope of ['current','proposal']){
   const subset=entries.map((e,i)=>({...e,id:plan.rootIds[i]})).filter(e=>e.scope===scope);if(!subset.length)continue;
   const {key,page}=pageFor(scope,row),start=positions.get(key),w=Math.max(...subset.map(e=>e.n.width)),h=Math.max(...subset.map(e=>e.n.height));
   g.createNode('TEXT',page.id,{name:row.area,text:row.area,fontFamily:'SF Pro',fontSize:28,fontWeight:700,width:Math.max(1000,w),height:40,x:64,y:start, fills:[{type:'SOLID',color:{r:.31,g:.48,b:.51,a:1},opacity:1,visible:true}]});
   for(let i=0;i<subset.length;i++){
    const e=subset[i];g.reparentNode(e.id,page.id);g.updateNode(e.id,{x:64+(i%3)*(w+80),y:start+80+Math.floor(i/3)*(h+80)});
    const sourcePage=e.scope==='current'?app:proposal;
    const svg=core.renderNodesToSVG(source,sourcePage.id,[e.n.id]);
    const keyName=(scope==='current'?row.keys:row.proposalKeys).find(k=>{const s=byKey.get(k);return e.n.name===`${s.device} / ${s.theme} / ${scope==='proposal'?'proposed-discover-':''}${s.spec} — ${s.title}`;});
    if(!keyName)throw Error('Artboard absent from inventory '+e.n.name);
    ledger.push({key:keyName,name:e.n.name,scope,file:row.file,page:page.name,id:e.id,svgSha256:sha(svg)});
   }
   positions.set(key,start+80+Math.ceil(subset.length/3)*(h+80)+100);
  }
  if((ordinal+1)%10===0||ordinal===rows.length)console.error(`Merged ${ordinal+1}/${rows.length}: ${ledger.length} artboards`);
 }
 beforeResources.nodes=g.nodes.size;beforeResources.components=[...g.getAllNodes()].filter(n=>n.type==='COMPONENT').length;beforeResources.variables=g.variables.size;
 const dedup={...deduplicateVariables(g),...deduplicateStyles(g),...deduplicateComponents(g)};
 const components=g.addPage('Components'),guide=g.addPage('Guide & Coverage'),internal=g.addPage('Internal Styles');g.updateNode(internal.id,{internalOnly:true});
 let gy=64;const guideHashes=new Set();
 // Shared definitions get one resource page. Only obsolete per-file scope cards are omitted.
 const masters=[...g.getAllNodes()].filter(n=>['COMPONENT','COMPONENT_SET'].includes(n.type)&&g.getNode(n.parentId)?.type!=='COMPONENT_SET');
 for(const n of masters)g.reparentNode(n.id,components.id);
 const libraryLayout=layoutLibrary(g,components);
 for(const n of [...g.getAllNodes()].filter(n=>n.sharedStyleType))g.reparentNode(n.id,internal.id);
 for(const p of resourcePages){if(!g.getNode(p.id))continue;for(const n of [...g.getChildren(p.id)]){
  if(n.name==='This file · scope and navigation'){g.deleteNode(n.id);continue;}
  if(!n.childIds.length&&n.type==='FRAME'&&n.name.startsWith('Discover Proposal')){g.deleteNode(n.id);continue;}
  if(!n.visible){g.reparentNode(n.id,internal.id);continue;}
  const props=walk(g,n.id).map(({id,parentId,childIds,source,x,y,...rest})=>rest),key=sha(props);
  if(guideHashes.has(key)){g.deleteNode(n.id);continue;}guideHashes.add(key);g.reparentNode(n.id,guide.id);g.updateNode(n.id,{x:64,y:gy});gy+=Math.max(n.height,80)+80;
 }g.deleteNode(p.id);}
 const text=(value,y,size=20)=>g.createNode('TEXT',cover.id,{name:value.split('\n')[0],text:value,fontFamily:'SF Pro',fontSize:size,fontWeight:size>28?700:400,lineHeight:Math.ceil(size*1.4),width:1200,height:Math.ceil(size*1.4)*value.split('\n').length,x:80,y,fills:[{type:'SOLID',color:{r:.04,g:.18,b:.2,a:1},opacity:1,visible:true}]});
 text('Gus — Complete App Designs',80,42);text(`${ledger.length.toLocaleString()} editable artboards · ${rows.length} source files combined`,160,26);
 text('App pages: current-app references at source checkpoint d715c05.\nProposal pages: expanded Seerr/Discover target designs.\nComponents and variables remain editable; shared resources are deduplicated.\nUse the platform and appearance pages in the left sidebar.\nThe browser review remains Exports/Preview/Preview.html.\nNative runtime and accessibility acceptance remain separate.',240);
 text([...pages.values()].map(p=>p.name).join('\n'),500,18);
 const checks=valid(g);
 let unchanged=0;for(const item of ledger){const n=g.getNode(item.id),svg=core.renderNodesToSVG(g,n.parentId,[n.id]);if(sha(svg)!==item.svgSha256)throw Error('Appearance changed during merge: '+item.key);unchanged++;}
 const bytes=await core.exportFigFile(g,undefined,undefined,cover.id,false);await fs.writeFile(output,bytes);
 const result={output,sourceFiles:rows.length,artboards:ledger.length,currentArtboards:ledger.filter(x=>x.scope==='current').length,proposalArtboards:ledger.filter(x=>x.scope==='proposal').length,pages:g.getPages().map(p=>p.name),bytes:bytes.length,libraryLayout,beforeResources,nodes:g.nodes.size,components:[...g.getAllNodes()].filter(n=>n.type==='COMPONENT').length,textStyles:[...g.getAllNodes()].filter(n=>n.sharedStyleType).length,variables:g.variables.size,dedup,unchangedScreenSVGs:unchanged,...checks};
 const metadata={result,inputs,artboards:ledger};await fs.writeFile(metadataPath(output),JSON.stringify(metadata,null,2));return result;
}
export async function verify(file=path.join(design,'Gus.fig')){
 const metadata=JSON.parse(await fs.readFile(metadataPath(file),'utf8')),g=await read(file),ns=[...g.getAllNodes()];const checks=valid(g);
 const visible=g.getPages(),lookup=new Map();for(const p of visible)for(const n of g.getChildren(p.id))lookup.set(p.name+'|'+n.name,n);
 for(const item of metadata.artboards){const n=lookup.get(item.page+'|'+item.name);if(!n)throw Error('Missing saved artboard '+item.key);if(sha(core.renderNodesToSVG(g,n.parentId,[n.id]))!==item.svgSha256)throw Error('Saved appearance differs '+item.key);item.id=n.id;item.pageId=n.parentId;}
 for(const input of metadata.inputs){if(sha(await fs.readFile(path.join(design,'Gus',input.file)))!==input.sha256)throw Error('Source changed '+input.file);}
 const result={passed:true,artboards:metadata.artboards.length,visiblePages:visible.length,components:ns.filter(n=>n.type==='COMPONENT').length,textLayers:ns.filter(n=>n.type==='TEXT').length,autoLayouts:ns.filter(n=>n.layoutMode!=='NONE').length,variables:g.variables.size,...checks,unchangedSavedScreenSVGs:metadata.artboards.length,sourceFilesUnchanged:metadata.inputs.length};
 metadata.verification=result;await fs.writeFile(metadataPath(file),JSON.stringify(metadata,null,2));return result;
}

export async function arrangeLibrary(file=path.join(design,'Gus.fig')){
 const g=await read(file),page=g.getPages().find(p=>p.name==='Components');
 const libraryLayout=layoutLibrary(g,page);
 const bytes=await core.exportFigFile(g,undefined,undefined,g.getPages()[0].id,false);await fs.writeFile(file,bytes);
 const metadata=JSON.parse(await fs.readFile(metadataPath(file),'utf8'));metadata.result.bytes=bytes.length;metadata.result.nodes=g.nodes.size;delete metadata.result.libraryGrid;metadata.result.libraryLayout=libraryLayout;await fs.writeFile(metadataPath(file),JSON.stringify(metadata,null,2));
 return {...libraryLayout,bytes:bytes.length};
}
