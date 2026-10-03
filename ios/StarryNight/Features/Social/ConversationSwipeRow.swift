import SwiftUI

/// A leftward drag makes room for inline actions at the trailing edge.
/// The buttons share the row's layout; they are never underneath its content.
/// The whole row tracks both opening and closing, including its action area.
/// Vertical drags scroll the list; confirmation owns expansion until finished.
struct ConversationSwipeRow<Content:View>:View {
    let id:String
    @Binding var revealedID:String?
    var locked:Bool
    var onOpen:()->Void
    var onHide:()->Void
    var onDelete:()->Void
    @ViewBuilder var content:()->Content
    @State private var dragging:CGFloat?
    @State private var origin:CGFloat=0
    @State private var ignoreTapUntil=Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let revealWidth:CGFloat=144
    private var reveal:CGFloat {dragging ?? (revealedID==id ? revealWidth : 0)}
    private var progress:CGFloat {reveal/revealWidth}
    private var motion:Animation {.spring(response:reduceMotion ? 0.18 : 0.32,dampingFraction:0.92)}
    var body:some View {
        HStack(spacing:0) {
            Button {
                // A simultaneous drag can finish before Button releases its
                // tracking touch. That release must not close the revealed row.
                guard Date()>=ignoreTapUntil else {return}
                if revealedID==id {withAnimation(motion) {revealedID=nil}}
                else {onOpen()}
            } label: {
                content().frame(maxWidth:.infinity,alignment:.leading)
                    .mask {
                        HStack(spacing:0) {
                            Rectangle().fill(.black)
                            LinearGradient(colors:[.black,.black.opacity(1-progress)],startPoint:.leading,endPoint:.trailing)
                                .frame(width:24)
                        }
                    }
            }
                .frame(maxWidth:.infinity).clipped().contentShape(Rectangle())
                .buttonStyle(ConversationRowButtonStyle()).accessibilityIdentifier("message-"+id)
                .allowsHitTesting(!locked)
            if reveal>0.1 {
                HStack(spacing:6) {
                    Button {if Date()>=ignoreTapUntil {onHide()}} label: {Text("不显示").frame(width:65,height:54).contentShape(Rectangle())}
                        .background(Theme.card,in:RoundedRectangle(cornerRadius:13))
                        .accessibilityIdentifier("hideConversation-"+id)
                    Button(role:.destructive) {if Date()>=ignoreTapUntil {onDelete()}} label: {Text("删除").frame(width:65,height:54).contentShape(Rectangle())}
                        .background(Color(hex:0xAC3E4E),in:RoundedRectangle(cornerRadius:13))
                        .accessibilityIdentifier("deleteConversation-"+id)
                }.font(.system(size:12,weight:.medium)).foregroundStyle(.white).buttonStyle(.plain)
                    .frame(width:136).frame(width:136*progress,alignment:.trailing).clipped()
                    .padding(.leading,8*progress).opacity(progress)
                    .allowsHitTesting(progress>0.95 && !locked).accessibilityHidden(progress<0.95)
                    .zIndex(1)
            }
        }.background(alignment:.trailing) {
            // One continuous surface crosses the content/action boundary. The
            // label's trailing mask blends into it instead of ending at a seam.
            LinearGradient(colors:[Theme.background.opacity(0),Theme.card.opacity(0.6),Color(hex:0xAC3E4E).opacity(0.12)],
                startPoint:.leading,endPoint:.trailing)
                .frame(width:reveal+32).clipShape(RoundedRectangle(cornerRadius:18))
                .opacity(progress).allowsHitTesting(false)
        }.clipped().contentShape(Rectangle())
            .background(ConversationRowPan(enabled:!locked,
                onChange:{translation,began in
                    ignoreTapUntil=Date().addingTimeInterval(0.3)
                    if began {origin=reveal;dragging=origin;revealedID=id}
                    dragging=min(revealWidth,max(0,origin-translation))
                },onEnd:{translation,velocity,cancelled in
                    ignoreTapUntil=Date().addingTimeInterval(0.3)
                    withAnimation(motion) {
                        revealedID=(cancelled ? origin : origin-translation-velocity*0.18)>revealWidth*0.5 ? id : nil
                        dragging=nil
                    }
                }))
            .accessibilityElement(children:.contain)
            .accessibilityAction(named:Text("不显示"),onHide)
            .accessibilityAction(named:Text("删除对话和记忆"),onDelete)
    }
}

/// Conversation rows keep their appearance while a finger rests or scrolls.
struct ConversationRowButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {configuration.label}
}

/// Reject vertical motion while UIKit is still deciding which recognizer owns
/// the touch. Returning from SwiftUI DragGesture.onChanged is already too late.
private struct ConversationRowPan:UIViewRepresentable {
    var enabled:Bool
    var onChange:(CGFloat,Bool)->Void
    var onEnd:(CGFloat,CGFloat,Bool)->Void
    func makeUIView(context:Context)->Anchor {Anchor()}
    func updateUIView(_ view:Anchor,context:Context) {view.options=self;view.install();view.pan.isEnabled=enabled}
    static func dismantleUIView(_ view:Anchor,coordinator:()) {view.detach()}
    final class Anchor:UIView,UIGestureRecognizerDelegate {
        var options:ConversationRowPan?
        weak var scroll:UIScrollView?
        lazy var pan:UIPanGestureRecognizer = {
            let value=UIPanGestureRecognizer(target:self,action:#selector(changed(_:)))
            value.maximumNumberOfTouches=1;value.delegate=self;return value
        }()
        init() {super.init(frame:.zero);isUserInteractionEnabled=false}
        required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
        override func didMoveToWindow() {super.didMoveToWindow();install()}
        override func didMoveToSuperview() {super.didMoveToSuperview();install()}
        func detach() {scroll?.removeGestureRecognizer(pan);scroll=nil}
        func install() {
            guard window != nil else {detach();return}
            var ancestor=superview
            while let view=ancestor {
                if let owner=view as? UIScrollView {
                    guard scroll !== owner else {return}
                    detach();scroll=owner;owner.addGestureRecognizer(pan)
                    owner.panGestureRecognizer.require(toFail:pan);return
                }
                ancestor=view.superview
            }
        }
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
            options?.enabled == true && bounds.contains(touch.location(in:self))
        }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer:UIGestureRecognizer)->Bool {
            let delta=pan.translation(in:window)
            // Consume either horizontal direction, including a rightward drag
            // on a closed row, so releasing it cannot become a button tap.
            // The row clamps that drag to zero; vertical motion still fails
            // before recognition and belongs to the scroll view.
            return options?.enabled == true && abs(delta.x)>abs(delta.y)*1.2
        }
        @objc func changed(_ gesture:UIPanGestureRecognizer) {
            let x=gesture.translation(in:window).x
            switch gesture.state {
            case .began,.changed:options?.onChange(x,gesture.state == .began)
            case .ended,.cancelled:options?.onEnd(x,gesture.velocity(in:window).x,gesture.state != .ended)
            default:break
            }
        }
    }
}
