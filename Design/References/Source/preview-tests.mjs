import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
let engine=fs.readFileSync(new URL('./preview-engine.js',import.meta.url),'utf8').replace('GUS_SCREEN_INDEX','[]').replace(/select\(\);\s*$/,'');
const el=()=>({add(){},addEventListener(){},replaceChildren(){},style:{},getBoundingClientRect(){return{left:0,top:0,width:400,height:800};}});const elements=new Map();const context={assert,console,Option:function(){},setTimeout,document:{querySelector(s){if(!elements.has(s))elements.set(s,el());return elements.get(s);}},window:{addEventListener(){}}};vm.createContext(context);
vm.runInContext(engine+`
current={w:400,h:800};
const content=()=>({setAttribute(k,v){this[k]=v}});
const outer={id:'outer',x:0,y:100,w:400,h:600,maxX:0,maxY:900,dx:0,dy:0,ancestors:[],content:content()};
const rail={id:'rail',x:0,y:300,w:400,h:200,maxX:500,maxY:0,dx:0,dy:0,ancestors:['outer'],content:content()};
regions=[outer,rail];hits=[{x:450,y:330,w:80,h:44,regions:['outer','rail'],b:{style:{}}}];
assert.equal(scroll([rail],200,0),true);assert.equal(rail.dx,200);assert.equal(hits[0].b.style.left,'62.5%');
assert.equal(scroll([rail],1e9,0),true);assert.equal(rail.dx,500);assert.equal(scroll([rail],100,0),false);
assert.equal(scroll([outer],0,250),true);assert.equal(outer.dy,250);assert.equal(relativeRect(rail).y,50);assert.equal(hits[0].b.hidden,false);
assert.equal(scroll([outer],0,1e9),true);assert.equal(outer.dy,900);assert.equal(hits[0].b.hidden,true);
assert.equal(scroll([outer],0,-1e9),true);assert.equal(outer.dy,0);
assert.equal(scroll([rail],-1e9,0),true);assert.equal(rail.dx,0);
`,context);console.log('PASS: nested scrolling, clamping, edge propagation and hotspot clipping');
