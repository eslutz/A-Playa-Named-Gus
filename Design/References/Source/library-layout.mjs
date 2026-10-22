/** Compact, size-aware resource layout; changes no component content. */
export function layoutLibrary(g,page){
 const nodes=g.getChildren(page.id).filter(n=>['COMPONENT','COMPONENT_SET'].includes(n.type));
 const groups=[['Symbols',n=>n.name.startsWith('SF Symbol /')],['Controls',n=>!n.name.startsWith('SF Symbol /')&&!n.name.startsWith('Art /')],['Artwork',n=>n.name.startsWith('Art /')&&n.width<=600],['Backdrops',n=>n.name.startsWith('Art /')&&n.width>600]];
 const width=2400,gap=48,margin=64,sections=[];let y=margin;
 for(const [name,match]of groups){
  const items=nodes.filter(match);if(!items.length)continue;
  const headingName='Library section / '+name;
  let heading=g.getChildren(page.id).find(n=>n.name===headingName);
  const props={name:headingName,text:name,fontFamily:'SF Pro',fontSize:32,fontWeight:700,x:margin,y,width,height:44,fills:[{type:'SOLID',color:{r:.19,g:.38,b:.41,a:1},opacity:1,visible:true}]};
  if(heading)g.updateNode(heading.id,props);else heading=g.createNode('TEXT',page.id,props);
  y+=88;let x=margin,rowHeight=0,rows=1;
  for(const n of items){
   const cellWidth=Math.max(220,n.width);
   if(x>margin&&x+cellWidth>margin+width){x=margin;y+=rowHeight+gap;rowHeight=0;rows++;}
   g.updateNode(n.id,{x,y});x+=cellWidth+gap;rowHeight=Math.max(rowHeight,n.height+32);
  }
  sections.push({name,components:items.length,rows});y+=rowHeight+112;
 }
 return {componentsArranged:nodes.length,width:width+2*margin,height:y,gap,sections};
}
