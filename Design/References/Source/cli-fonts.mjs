// Load the installed static Apple faces into the CLI's font manager.
// This changes only the current CLI process; it does not install or rewrite fonts.
import fs from 'node:fs';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const root=process.env.GUS_OPENPENCIL_CLI_ROOT||'/private/tmp/gus-openpencil-cli';
const require=createRequire(root+'/package.json');
const {fontManager}=await import(pathToFileURL(require.resolve('@open-pencil/core/text')).href);
fontManager.setOnlineFontProviders({});
fontManager.setWebFontFetch(null);
for(const[family,prefix]of [['SF Pro','SF-Pro-Text-'],['SF Compact','SF-Compact-Text-']]){
  for(const style of ['Regular','Medium','Semibold','Bold']){
    const b=fs.readFileSync('/Library/Fonts/'+prefix+style+'.otf');
    const data=b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength);
    fontManager.markLoaded(family,style,data,'local');
    if(style==='Semibold')fontManager.markLoaded(family,'SemiBold',data,'local');
  }
}
