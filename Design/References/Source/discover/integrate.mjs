import {sdkRoot} from '../sdk.mjs';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const sdk=sdkRoot;
const core=await import(sdk+'/core/dist/index.js');
const {prepareGraphTransfer,applyGraphTransfer}=await import(sdk+'/scene-graph/dist/index.js');
const input=path.resolve(process.env.GUS_DISCOVER_BUILD_DIR||'/tmp/gus-discover-design');
const sourceFile=process.env.GUS_DISCOVER_SOURCE||path.join(input,'Gus — Seerr Experience.fig');
const read=async file=>{const b=fs.readFileSync(file);return core.parseFigFile(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),{populate:'all'});};
const source=await read(sourceFile);
const sourceScenes=JSON.parse(fs.readFileSync(path.join(path.dirname(sourceFile),'scenes.json')));
const layouts={'iPhone':'iPhone','iPad':'iPad Landscape','iPad Portrait':'iPad','Mac':'macOS','Mac Narrow':'macOS Narrow','Apple TV':'tvOS','Vision':'visionOS'};
const children=(g,id)=>g.getChildren(id).flatMap(n=>[n,...children(g,n.id)]);
const hash=s=>crypto.createHash('sha256').update(s).digest('hex');
const titles={catalog:'Catalog Grid',person:'Person & Credits',managerfilters:'Request Filters',unsupported:'Unsupported Server',signinerror:'Sign-in Error',servererror:'Connection Error',partial:'Partial Catalog Failure',permission:'Permission Changed',mutationerror:'Request Rejected',browse:'Browse',movie:'Movie Details',show:'Series Details',request:'Request Seasons',requestmovie:'Request Movie',advanced:'Series Request Options',advancedmovie:'Movie Request Options',sentmovie:'Movie Request Sent',sent:'Series Request Sent',myrequests:'My Requests',requestdetail:'Request Details',manager:'Manage Requests',approval:'Review Request',titlemenu:'Title Options',blocklist:'Blocked Titles',notifications:'Notifications',blockconfirm:'Block Title',accessibility:'Accessibility Layout',empty:'No Results',expired:'Session Expired',quota:'Quota Reached',uncertain:'Uncertain Request',disconnect:'Disconnect',hide:'Hide Discover',available:'Available in Gus',welcome:'First Use',signin:'Sign In',server:'Server URL',detail:'Title Details'};
const owns=n=>n.name==='Discover Proposal'||n.name==='Discover Proposal Resources'||n.name==='Discover Proposal Guide'||n.name==='Discover Proposal Styles';
const groups=new Map();
for(const s of sourceScenes){const device=layouts[s.device];if(!device)throw Error('Unknown layout '+s.device);const file=`${device.replaceAll(' ','-')}/${s.theme}/05 Discover.fig`;if(!groups.has(file))groups.set(file,[]);groups.get(file).push({...s,device,originalName:s.name,scope:'proposal',feature:'discover',spec:s.state,key:`${device.replaceAll(' ','-')}-${s.theme}-proposed-discover-${s.state}`,title:`Discover · ${titles[s.state]||s.state.charAt(0).toUpperCase()+s.state.slice(1)}`,file});}

const report=[],newScenes=[],ledger=[];
for(const [file,scenes]of groups){
 const targetFile=path.join(base,'../Gus',file),g=await read(targetFile);
 const app=g.getPages().find(p=>p.name==='App Screens'),guide=g.getPages().find(p=>p.name==='Guide & Coverage'),components=g.getPages().find(p=>p.name==='Components');
 if(!app||!guide||!components)throw Error('Missing standard pages '+file);
 const oldPage=g.getPages().find(p=>p.name==='Discover Proposal');
 const oldProposal=new Map((oldPage?g.getChildren(oldPage.id):[]).map(n=>[n.name,hash(core.renderNodesToSVG(g,oldPage.id,[n.id]))]));
 const current=g.getChildren(app.id),before=current.map(n=>hash(core.renderNodesToSVG(g,app.id,[n.id])));
 // Regeneration replaces only the previously imported proposal resources.
 for(const n of [...g.getAllNodes()].filter(owns))if(g.getNode(n.id))g.deleteNode(n.id);
 for(const n of [...g.getAllNodes()].filter(n=>n.sharedStyleType&&(/^(Type \/|Discover Proposal \/)/).test(n.name)))g.deleteNode(n.id);
 for(const coll of [...g.variableCollections.values()])if(coll.name.startsWith('Discover Proposal /'))g.removeCollection(coll.id);
 const proposal=g.addPage('Discover Proposal');
 const sourceBoards=scenes.map(s=>[...source.getAllNodes()].find(n=>n.name===s.originalName));
 if(sourceBoards.some(n=>!n))throw Error('Missing source artboard '+file);
 const dependencies=source.getPages(true).filter(p=>p.internalOnly||['05 · Components','06 · Read Me'].includes(p.name));
 const plan=prepareGraphTransfer({source,rootIds:sourceBoards.map(n=>n.id),dependencyPageIds:dependencies.map(p=>p.id),target:g,parentId:proposal.id});
 for(const entry of plan.nodes)if(plan.dependencyPageIds.includes(entry.id))entry.props.internalOnly=true;
 for(const entry of plan.nodes)if(entry.props.sharedStyleType)entry.props.name='Discover Proposal /'+entry.props.name;
 applyGraphTransfer(g,plan);
 for(const coll of plan.collections)g.variableCollections.get(coll.id).name='Discover Proposal /'+coll.name;
 for(const id of plan.dependencyPageIds){
  const p=g.getNode(id);if(!['05 · Components','06 · Read Me'].includes(p.name)){g.updateNode(id,{name:'Discover Proposal Styles'});continue;}
  const isComponents=p.name==='05 · Components',parent=isComponents?components:guide,name=isComponents?'Discover Proposal Resources':'Discover Proposal Guide';
  const existing=g.getChildren(parent.id),y=Math.max(0,...existing.map(n=>n.y+n.height))+120;
  const nodes=g.getChildren(id),w=Math.max(1800,...nodes.map(n=>n.x+n.width)),h=Math.max(200,...nodes.map(n=>n.y+n.height));
  const section=g.createNode('FRAME',parent.id,{name,x:80,y,width:w,height:h,fills:[],clipsContent:false});
  for(const child of nodes)g.reparentNode(child.id,section.id);
  if(!isComponents)for(const n of children(g,section.id).filter(n=>n.type==='TEXT'))g.updateNode(n.id,{text:n.text.replace('Review 01 for browsing/requesting, 02 for management/recovery, 03 for iPad/Mac, 04 for TV/Vision.','Use this file’s Discover Proposal page; the current app remains on App Screens.').replace('The companion Review.html provides working local navigation between represented screens.','The shared Preview.html provides synthetic navigation in Discover proposal mode.').replace('See SPEC.md','See DISCOVER.md').replace('QA reports and per-screen previews are saved beside this file.','References/QA/Discover holds integrated validation and review images.')});
  g.deleteNode(id);
 }
 const maxW=Math.max(...scenes.map(s=>s.w)),maxH=Math.max(...scenes.map(s=>s.h));
 for(let i=0;i<scenes.length;i++){
  const s=scenes[i],n=g.getNode(plan.rootIds[i]);
  g.updateNode(n.id,{name:`${s.device} / ${s.theme} / proposed-discover-${s.state} — ${s.title}`,x:64+(i%3)*(maxW+64),y:64+Math.floor(i/3)*(maxH+80)});
  const svg=core.renderNodesToSVG(g,proposal.id,[n.id]);
  const baseline=core.renderNodesToSVG(source,sourceBoards[i].parentId,[sourceBoards[i].id]);
  if(svg!==baseline){fs.writeFileSync('/tmp/gus-discover-integration/before.svg',baseline);fs.writeFileSync('/tmp/gus-discover-integration/after.svg',svg);throw Error('Proposal appearance changed on transfer: '+s.originalName);}
  s.svg=baseline;
  newScenes.push({...s,svg,scrollRegions:[],links:s.links});
 }
 const data=await core.exportFigFile(g,undefined,undefined,app.id,false);
 const rb=await core.parseFigFile(data.buffer.slice(data.byteOffset,data.byteOffset+data.byteLength),{populate:'all'});
 const page=rb.getPages().find(p=>p.name==='Discover Proposal'),ns=[...rb.getAllNodes()],saved=rb.getChildren(page.id),styles=new Set(ns.filter(n=>n.sharedStyleType==='TEXT').flatMap(n=>[n.id,n.source.id]));
 const errors={instances:ns.filter(n=>n.type==='INSTANCE'&&!rb.getNode(n.componentId)).length,styles:ns.filter(n=>n.textStyleId&&!styles.has(n.textStyleId)).length,geometry:ns.filter(n=>['x','y','width','height'].some(k=>!Number.isFinite(n[k]))).length};
 const afterApp=rb.getPages().find(p=>p.name==='App Screens');
 const after=rb.getChildren(afterApp.id).map(n=>hash(core.renderNodesToSVG(rb,afterApp.id,[n.id])));
 if(before.length!==after.length||before.some((h,i)=>h!==after[i])||saved.length!==scenes.length||Object.values(errors).some(Boolean))throw Error('Integrated readback failed '+JSON.stringify({file,errors,before:before.length,after:after.length,saved:saved.length,expected:scenes.length,currentChanged:before.filter((h,i)=>h!==after[i]).length}));
 for(let i=0;i<scenes.length;i++){
  const s=scenes[i],n=saved[i],svg=core.renderNodesToSVG(rb,page.id,[n.id]);if(svg!==s.svg)throw Error('Saved proposal pixels differ '+s.key);
  ledger.push({...s,svg:undefined,id:n.id,pageId:page.id,name:n.name,layers:children(rb,n.id).length});
 }
 const unchangedProposalStates=scenes.filter(s=>oldProposal.get(`${s.device} / ${s.theme} / proposed-discover-${s.state} — ${s.title}`)===hash(s.svg)).map(s=>s.key);
 const changedProposalStates=scenes.filter(s=>!unchangedProposalStates.includes(s.key)).map(s=>s.key);
 if(process.argv.includes('--narrow-fix')&&changedProposalStates.some(k=>k!=='macOS-Narrow-Light-proposed-discover-detail'))throw Error('Unexpected visual change '+JSON.stringify(changedProposalStates));
 const r={file,unchangedProposalStates,changedProposalStates,currentArtboards:current.length,proposalArtboards:saved.length,currentAppearanceUnchanged:true,proposalAppearanceUnchanged:true,...errors,pages:rb.getPages().map(p=>p.name),bytes:data.length,variables:rb.variables.size,textStyles:ns.filter(n=>n.sharedStyleType==='TEXT').length};report.push(r);
 if(process.argv.includes('--pilot')){fs.writeFileSync('/tmp/gus-discover-integration/pilot.fig',data);console.log(JSON.stringify(r));break;}
 fs.writeFileSync(targetFile,data);console.log('Integrated',file,scenes.length);
}
if(!process.argv.includes('--pilot')){
 if(ledger.length!==sourceScenes.length)throw Error('Missing source proposal artboards');
 const indexFile=path.join(base,'../Gus/index.json'),index=JSON.parse(fs.readFileSync(indexFile));
 for(const row of index.files){const added=report.find(r=>r.file===row.file);if(!added)continue;Object.assign(row,{proposalArtboards:added.proposalArtboards,proposalPage:'Discover Proposal',proposalKeys:ledger.filter(s=>s.file===row.file).map(s=>s.key),bytes:added.bytes,textStyles:added.textStyles,variables:added.variables});}
 index.proposalArtboards=ledger.length;index.totalArtboards=index.artboards+ledger.length;fs.writeFileSync(indexFile,JSON.stringify(index,null,2));
 const manifestFile=path.join(base,'Source/screen-manifest.json'),manifest=JSON.parse(fs.readFileSync(manifestFile)).filter(s=>s.scope!=='proposal');
 const discoverKeys=new Set(index.files.filter(r=>r.area==='05 Discover').flatMap(r=>r.keys));
 for(const s of manifest){s.scope='current';if(discoverKeys.has(s.key))s.feature='discover';}
 for(const s of newScenes){fs.writeFileSync(path.join(base,'../Exports/Preview/preview-scenes',s.key+'.js'),'window.GusPreview.register('+JSON.stringify(s).replaceAll('</script','<\\/script')+');');}
 fs.writeFileSync(manifestFile,JSON.stringify([...manifest,...newScenes.map(({svg,...s})=>s)],null,2));
 const qa=path.join(base,'QA/Discover');fs.mkdirSync(qa,{recursive:true});
 fs.writeFileSync(path.join(qa,'integration.json'),JSON.stringify({artboards:ledger.length,integratedFiles:report.length,files:report},null,2));
 fs.writeFileSync(path.join(base,'Source/discover/manifest.json'),JSON.stringify(ledger,null,2));
}
