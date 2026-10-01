import Foundation
import CoreGraphics

@main enum CharacterArtworkLayoutTests {
static func main() throws {
struct ArtworkCatalog:Decodable {struct Entry:Decodable {let runtimeID:String;let headBounds:CharacterHeadBounds};let covers:[Entry]}
let data=try Data(contentsOf:URL(fileURLWithPath:"ios/CharacterHost/Resources/CharacterCoverCatalog.json"))
let catalog=try JSONDecoder().decode(ArtworkCatalog.self,from:data)
var checks=0
for entry in catalog.covers {
 for size in [CGSize(width:28,height:28),CGSize(width:42,height:42),CGSize(width:96,height:96)] {
  let f=CharacterArtworkLayout.frame(source:CGSize(width:1536,height:2048),target:size,head:entry.headBounds,circle:true)
  let b=entry.headBounds
  for x in [b.x,b.x+b.width] {for y in [b.y,b.y+b.height] {
   let p=CGPoint(x:f.minX+x*f.width-size.width/2,y:f.minY+y*f.height-size.height/2)
   assert(hypot(p.x,p.y)<=size.width*0.461,entry.runtimeID+" clipped head in circle");checks+=1
  }}
 }
 for (size,banner) in [(CGSize(width:180,height:250),false),(CGSize(width:360,height:130),true),(CGSize(width:402,height:874),false),(CGSize(width:874,height:402),false)] {
  let f=CharacterArtworkLayout.frame(source:CGSize(width:1536,height:2048),target:size,head:entry.headBounds,circle:false,banner:banner)
  let b=entry.headBounds
  let r=CGRect(x:f.minX+b.x*f.width,y:f.minY+b.y*f.height,width:b.width*f.width,height:b.height*f.height)
  assert(r.minX>=0 && r.minY>=0 && r.maxX<=size.width && r.maxY<=size.height,entry.runtimeID+" clipped cover head");checks+=1
 }
}
print("Artwork head-framing checks:",checks,"passed")

}
}
