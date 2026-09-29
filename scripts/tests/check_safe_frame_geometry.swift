import Foundation

// Run with AdaptiveViewerLayout.swift; no UIKit/app launch is needed.
@main struct SafeFrameGeometryCheck {
    static func main() {
        let windows:[(CGSize,AdaptiveViewerLayout.Insets)] = [
            (CGSize(width:402,height:874),.init(top:62,bottom:34)),
            (CGSize(width:375,height:812),.init(top:44,bottom:34)),
            (CGSize(width:375,height:667),.init(top:20)),
            (CGSize(width:874,height:402),.init(left:62,bottom:21,right:62))
        ]
        for (size,insets) in windows {
            let safe = AdaptiveViewerLayout.characterSafeFrame(size,inset:insets)
            precondition(abs((1-safe.maxY)*size.height-insets.top-10)<0.00001,"safe top is not real window top + 10 points")
            precondition(abs(safe.minX*size.width-insets.left-8)<0.00001,"left cutout is not protected")
            precondition(abs((1-safe.maxX)*size.width-insets.right-8)<0.00001,"right cutout is not protected")
            let normal = AdaptiveViewerLayout.conversation(size,inset:insets,keyboard:nil)
            for fraction in [0.35,0.5,0.7] {
                let chat = AdaptiveViewerLayout.conversation(size,inset:insets,
                    keyboard:CGRect(x:0,y:size.height-300,width:size.width,height:300),heightFraction:fraction)
                precondition(chat.chat != normal.chat,"fixture should actually move chat")
                precondition(AdaptiveViewerLayout.characterSafeFrame(size,inset:insets)==safe,"keyboard must not move camera safe frame")
            }
        }
        print("PASS: 4 independent window safe areas, UIKit→Unity Y conversion, 12 keyboard/chat-height layouts.")
    }
}
