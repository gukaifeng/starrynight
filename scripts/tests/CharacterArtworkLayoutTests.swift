import Foundation
import CoreGraphics

@main enum CharacterArtworkLayoutTests {
static func main() throws {
struct ArtworkCatalog:Decodable {struct Entry:Decodable {let runtimeID:String;let headBounds:CharacterHeadBounds};let covers:[Entry]}
let data=try Data(contentsOf:URL(fileURLWithPath:"ios/StarryNight/Resources/CharacterCoverCatalog.json"))
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
 for (size,banner) in [(CGSize(width:180,height:250),false),(CGSize(width:360,height:130),true),(CGSize(width:358,height:298.34),true),(CGSize(width:520,height:433.34),true),(CGSize(width:402,height:874),false),(CGSize(width:874,height:402),false)] {
  let f=CharacterArtworkLayout.frame(source:CGSize(width:1536,height:2048),target:size,head:entry.headBounds,circle:false,banner:banner)
  let b=entry.headBounds
  let r=CGRect(x:f.minX+b.x*f.width,y:f.minY+b.y*f.height,width:b.width*f.width,height:b.height*f.height)
  assert(f.minX<=0.01 && f.minY<=0.01 && f.maxX>=size.width-0.01 && f.maxY>=size.height-0.01,entry.runtimeID+" cover has an uncovered edge");checks+=1
  // A landscape aperture may be shorter than the head at aspect-fill scale.
  // Preserve the whole head on each axis where the actual geometry allows it.
  if r.width<=size.width {assert(r.minX>=(-0.01) && r.maxX<=size.width+0.01);checks+=1}
  if r.height<=size.height*0.84 {assert(r.minY>=(-0.01) && r.maxY<=size.height+0.01);checks+=1}
 }
}
print("Artwork head-framing checks:",checks,"passed")

}
}
