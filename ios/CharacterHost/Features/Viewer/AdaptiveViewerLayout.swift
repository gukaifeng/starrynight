import Foundation
import CoreGraphics

/// Window geometry is the source of truth, including iPad resizable windows.
/// The returned stage is a composition target; Unity always renders the full window.
enum AdaptiveViewerLayout {
    struct Insets { var top:CGFloat = 0; var left:CGFloat = 0; var bottom:CGFloat = 0; var right:CGFloat = 0 }
    struct Layout { var side:Bool; var chat:CGRect; var stage:CGRect }
    static func sideBySide(_ size:CGSize) -> Bool { size.width >= 680 && size.width > size.height * 1.08 }
    static func safeRect(_ size:CGSize,_ inset:Insets) -> CGRect {
        CGRect(x:inset.left,y:inset.top,width:max(1,size.width-inset.left-inset.right),height:max(1,size.height-inset.top-inset.bottom))
    }
    static func normalized(_ rect:CGRect,in size:CGSize) -> CGRect {
        let visible = rect.intersection(CGRect(origin:.zero,size:size))
        guard !visible.isNull, size.width > 0, size.height > 0 else { return CGRect(x:0,y:0,width:1,height:1) }
        return CGRect(x:visible.minX/size.width,y:1-visible.maxY/size.height,width:visible.width/size.width,height:visible.height/size.height)
    }
    /// Hardware/window insets define headroom, with a little space above the hair.
    /// Transient sheets, the keyboard, chat height and the dock never enter this calculation.
    static func characterSafeFrame(_ size:CGSize,inset:Insets) -> CGRect {
        let safe = safeRect(size,inset)
        let top = min(safe.maxY-1,safe.minY+10)
        let margin = min(8,max(0,(safe.width-1)/2))
        return normalized(CGRect(x:safe.minX+margin,y:top,width:max(1,safe.width-2*margin),height:max(1,safe.maxY-top)),in:size)
    }
    static func sheet(_ size:CGSize,inset:Insets,preferred:CGSize,expanded:Bool) -> CGRect {
        let safe = safeRect(size,inset)
        if sideBySide(size) {
            let width = min(max(320,safe.width * 0.43),min(480,max(320,preferred.width)))
            let top = safe.minY + 72
            return CGRect(x:safe.maxX-width-8,y:top,width:width,height:max(120,safe.maxY-top-8))
        }
        let available = max(120,safe.maxY-safe.minY-28)
        let height = expanded ? available : min(available,preferred.height+inset.bottom)
        let width = size.width >= 700 ? min(safe.width-48,preferred.width) : safe.width
        return CGRect(x:safe.midX-width/2,y:size.height-height,width:width,height:height)
    }
    /// Wide, tall panels become solid; short previews and landscape sidebars keep the scene visible.
    /// The continuous ramp also follows an interactive expansion without a sudden surface change.
    static func sheetSurfaceOpacity(_ frame:CGRect,in size:CGSize,inset:Insets) -> CGFloat {
        let safe = safeRect(size,inset)
        let visible = frame.intersection(safe)
        guard !visible.isNull, visible.width >= safe.width * 0.65 else { return 0 }
        let progress = min(1,max(0,(visible.height / safe.height - 0.72) / 0.18))
        return progress * progress * (3-2*progress)
    }
    static func conversation(_ size:CGSize,inset:Insets,keyboard:CGRect?,heightFraction:CGFloat = 0.5) -> Layout {
        let safe = safeRect(size,inset), side = sideBySide(size)
        let top = safe.minY + (side ? 68 : 76)
        let bottom = safe.maxY - 10
        let width = side ? min(440,max(300,safe.width * 0.41)) : min(safe.width,700)
        let x = side ? safe.maxX-width-8 : safe.midX-width/2
        var chatBottom = bottom
        var dockedTop = bottom
        if let keyboard, keyboard.height > 35, keyboard.minY < bottom,
           keyboard.intersects(CGRect(x:x,y:top,width:width,height:max(1,bottom-top))) {
            chatBottom = max(top+68,min(bottom,keyboard.minY-8))
            if keyboard.width >= safe.width * 0.7 && keyboard.maxY >= safe.maxY-8 { dockedTop = chatBottom }
        }
        let available = max(68,chatBottom-top)
        let fraction = heightFraction.isFinite ? min(0.70,max(0.35,heightFraction)) : 0.5
        let height = side ? min(available,max(200,available*fraction/0.5)) :
            min(available,keyboard == nil ? size.height*fraction : max(200,available*min(1,fraction/0.5*0.7)))
        let chat = CGRect(x:x,y:chatBottom-height,width:width,height:height)
        let stage = side ? CGRect(x:safe.minX+8,y:top,width:max(120,x-safe.minX-24),height:max(80,dockedTop-top)) : CGRect(origin:.zero,size:size)
        return Layout(side:side,chat:chat,stage:stage)
    }
}
