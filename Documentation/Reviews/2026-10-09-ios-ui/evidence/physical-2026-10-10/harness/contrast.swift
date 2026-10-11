import AppKit
let file=CommandLine.arguments[1]
let bitmap=NSBitmapImageRep(data:try Data(contentsOf:URL(fileURLWithPath:file)))!
var counts:[String:Int]=[:]
for y in 1130..<1190 {for x in 1190..<1670 {
 if let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) {
 let k=String(format:"#%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded()))
 counts[k,default:0]+=1
 }
}}
print(counts.sorted{$0.value>$1.value}.prefix(6))
func lin(_ v:Double)->Double {let s=v/255;return s<=0.04045 ? s/12.92:pow((s+0.055)/1.055,2.4)}
let l=0.2126*lin(184)+0.7152*lin(227)+0.0722*lin(233)
print("White/source-accent contrast",1.05/(l+0.05))
