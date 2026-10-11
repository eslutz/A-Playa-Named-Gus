import subprocess,time,sys,json,pathlib
p,udid,suffix=sys.argv[1:4]
root=pathlib.Path.cwd(); out=root/'Documentation/Reviews/2026-10-09-ios-ui/evidence/multiplatform-2026-10-10'/p;out.mkdir(exist_ok=True)
app=root/'build/DerivedData/Build/Products'/('Debug-'+suffix)/'A Playa Named Gus.app'
bundle='dev.ericslutz.gus'
def run(*a,check=True):return subprocess.run(['xcrun','simctl',*a],check=check,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
run('boot',udid,check=False);run('bootstatus',udid,'-b');run('install',udid,str(app))
items=json.load(open('/tmp/gus-multiplatform-audit/demo-items.json'))
scenes=[('01-connect',['--gus-skip-session-restore']),('02-home',[]),('03-libraries',['--gus-route','libraries']),('04-settings',['--gus-route','settings']),('05-search',['--gus-route','search'])]
for n,typ in [('06-movie','Movie'),('07-album','MusicAlbum'),('08-book','Book'),('09-photo','Photo')]:
 x=next(x for x in items if x['Type']==typ);scenes.append((n,['--gus-route','item/'+x['Id']]))
x=next(x for x in items if x['Type']=='Movie');scenes.append(('10-player',['--gus-route','play/'+x['Id']]))
for n,args in scenes:
 run('terminate',udid,bundle,check=False)
 run('launch',udid,bundle,*(([] if n=='01-connect' else ['--gus-demo-server'])+args))
 time.sleep(7)
 run('io',udid,'screenshot',str(out/(n+'.png')))
 print(p,n,flush=True)
run('terminate',udid,bundle,check=False)
