import pathlib,sys,subprocess,json,shutil
name,folder=sys.argv[1:3]
t=pathlib.Path('/tmp/gus-multiplatform-audit');p=t/(name+'-attachments')
subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(t/(name+'.xcresult')),'--output-path',str(p)],check=True,stdout=subprocess.DEVNULL)
o=pathlib.Path('Documentation/Reviews/2026-10-09-ios-ui/evidence/multiplatform-2026-10-10')/folder;o.mkdir(exist_ok=True)
for test in json.loads((p/'manifest.json').read_text()):
 for a in test['attachments']:
  src=p/a['exportedFileName'];n=a['suggestedHumanReadableName'].split('_0_')[0]
  shutil.copy2(src,o/(n+src.suffix))
shutil.copy2(t/(name+'.log'),o/(name+'.log'))
print('Exported',len(list(o.glob('*'))),'files to',o)
