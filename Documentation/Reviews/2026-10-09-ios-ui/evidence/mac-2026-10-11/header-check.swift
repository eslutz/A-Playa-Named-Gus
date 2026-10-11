import Foundation
for (label,device) in [("ASCII", "Audit Mac"),("Unicode", "Audit’s Mac")] {
 var r=URLRequest(url:URL(string:"http://localhost:8096/Users/AuthenticateByName")!)
 r.httpMethod="POST"
 r.setValue("application/json",forHTTPHeaderField:"Content-Type")
 r.setValue("MediaBrowser DeviceId=gus-audit-header, Device=\(device), Client=A Playa Named Gus macOS, Version=1.0.0",forHTTPHeaderField:"Authorization")
 r.httpBody=try JSONSerialization.data(withJSONObject:["Username":"gus","Pw":"playa-demo"])
 let (_,response)=try await URLSession.shared.data(for:r)
 print("\(label) device header: HTTP \((response as! HTTPURLResponse).statusCode)")
}
