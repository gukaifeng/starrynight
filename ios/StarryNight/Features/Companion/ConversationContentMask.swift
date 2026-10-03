import SwiftUI

/// Screen-fixed alpha for the entire rendered message layer: text, bubble,
/// streaming reply and message actions fade together while scrolling through it.
/// The room veil keeps its gentler smoothstep; this squared curve disappears
/// earlier and removes the old 80-point strip at the conversation boundary.
struct ConversationContentMask: View {
    var reduceTransparency: Bool
    static func readableStart(in height: CGFloat) -> CGFloat {
        min(max(1,height) * 0.82,max(0,height-64))
    }
    // Below ~2% content opacity there is no usable bubble target. Let that
    // visually empty strip participate in touching the character behind it.
    static func touchThroughHeight(in height: CGFloat) -> CGFloat { readableStart(in:height) * 0.32 }

    var body: some View {
        GeometryReader { geometry in
            if reduceTransparency {
                Rectangle().fill(.black)
            } else {
                let height = max(1,geometry.size.height)
                // Reserve room for a readable recent message when a keyboard makes
                // the window short. Otherwise the transition spans most of the list.
                let end = Self.readableStart(in:height) / height
                let start = end * 0.12
                let bottomFeather = min(16,height * 0.08) / height
                LinearGradient(stops:(0...32).map { index in
                    let position = CGFloat(index)/32
                    let t = end > 0 ? min(1,max(0,(position-start)/(end-start))) : 1
                    let eased = t*t*(3-2*t)
                    // Scrolled bubbles also dissolve just before the fixed controls;
                    // the list's bottom padding keeps the latest actions outside it.
                    let tail = min(1,max(0,(1-position)/bottomFeather))
                    let lowerEdge = tail*tail*(3-2*tail)
                    return Gradient.Stop(color:.black.opacity(Double(eased*eased*lowerEdge)),location:position)
                },startPoint:.top,endPoint:.bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
