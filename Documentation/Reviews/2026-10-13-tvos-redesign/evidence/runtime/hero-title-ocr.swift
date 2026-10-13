import Foundation
import Vision
import ImageIO
let url=URL(fileURLWithPath:CommandLine.arguments[1])
let request=VNRecognizeTextRequest()
request.recognitionLevel = .accurate
try VNImageRequestHandler(url:url).perform([request])
for observation in request.results ?? [] {
 if let text=observation.topCandidates(1).first?.string {
  print(String(format:"%.3f %.3f %.3f %.3f",observation.boundingBox.minX,observation.boundingBox.minY,observation.boundingBox.width,observation.boundingBox.height)+" "+text)
 }
}
