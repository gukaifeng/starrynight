import Foundation
import CoreGraphics

/// Normalized bounds include head, ears, hat and ornaments (not trailing hair).
/// Both circle portraits and wide banners use the same reviewed source artwork.
struct CharacterHeadBounds:Codable,Sendable {
    var x:CGFloat;var y:CGFloat;var width:CGFloat;var height:CGFloat
    var rect:CGRect {CGRect(x:x,y:y,width:width,height:height)}
}
enum CharacterArtworkLayout {
    static func frame(source:CGSize,target:CGSize,head:CharacterHeadBounds,circle:Bool,banner:Bool=false)->CGRect {
        guard source.width>0,source.height>0,target.width>0,target.height>0 else {return .zero}
        let box=CGRect(x:head.x*source.width,y:head.y*source.height,width:head.width*source.width,height:head.height*source.height)
        guard box.width>0,box.height>0 else {return .zero}
        let scale:CGFloat,center:CGPoint
        if circle {
            // Fit the entire head rectangle inside the circular aperture, with
            // a small breathing margin; a square aspect-fill crop cannot do this.
            scale=min(target.width,target.height)*0.92/hypot(box.width,box.height)
            center=CGPoint(x:target.width/2,y:target.height/2)
        } else {
            // Fill every edge with the actual artwork. Focal positioning keeps
            // the head in view where the aperture permits, without side mattes.
            let fill=max(target.width/source.width,target.height/source.height)
            scale=max(fill,min(target.width*0.92/box.width,target.height*(banner ? 0.84:0.64)/box.height))
            // Very wide/short apertures cannot contain the full head at fill
            // scale. Center that crop lower on the head so a hat cannot replace
            // the face. Normal portrait and profile apertures retain headroom.
            let headHeight=box.height*scale
            let headCenter=headHeight > target.height*0.92 ? target.height*0.53-headHeight*0.12 : target.height*(banner ? 0.08:0.055)+headHeight/2
            center=CGPoint(x:target.width/2,y:headCenter)
        }
        let width=source.width*scale,height=source.height*scale
        let x=center.x-box.midX*scale,y=center.y-box.midY*scale
        return CGRect(x:circle ? x : min(0,max(target.width-width,x)),
                      y:circle ? y : min(0,max(target.height-height,y)),width:width,height:height)
    }
}
