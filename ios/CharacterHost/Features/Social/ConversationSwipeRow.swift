import SwiftUI

/// A leftward drag makes room for inline actions at the trailing edge.
/// The buttons share the row's layout; they are never underneath its content.
/// Vertical/rightward drags do not reveal actions, and confirmation owns the
/// expanded state until it finishes.
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
    @State private var axis=0
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
            } label: {content().frame(maxWidth:.infinity,alignment:.leading)}
                .frame(maxWidth:.infinity).clipped().contentShape(Rectangle())
                .buttonStyle(.plain).accessibilityIdentifier("message-"+id)
                .allowsHitTesting(!locked)
                .simultaneousGesture(revealGesture)
            if reveal>0.1 {
                HStack(spacing:6) {
                    Button(action:onHide) {Text("不显示").frame(width:65,height:54).contentShape(Rectangle())}
                        .background(Theme.card,in:RoundedRectangle(cornerRadius:13))
                        .accessibilityIdentifier("hideConversation-"+id)
                    Button(role:.destructive,action:onDelete) {Text("删除").frame(width:65,height:54).contentShape(Rectangle())}
                        .background(Color(hex:0xAC3E4E),in:RoundedRectangle(cornerRadius:13))
                        .accessibilityIdentifier("deleteConversation-"+id)
                }.font(.system(size:12,weight:.medium)).foregroundStyle(.white).buttonStyle(.plain)
                    .frame(width:136).frame(width:136*progress,alignment:.trailing).clipped()
                    .padding(.leading,8*progress).opacity(progress)
                    .allowsHitTesting(progress>0.95 && !locked).accessibilityHidden(progress<0.95)
                    .zIndex(1)
            }
        }.clipped().accessibilityElement(children:.contain)
            .accessibilityAction(named:Text("不显示"),onHide)
            .accessibilityAction(named:Text("删除对话和记忆"),onDelete)
    }
    private var revealGesture:some Gesture {
        DragGesture(minimumDistance:12,coordinateSpace:.global).onChanged {value in
                guard !locked else {return}
                ignoreTapUntil=Date().addingTimeInterval(0.3)
                if axis==0 {
                    guard -value.translation.width>abs(value.translation.height)*1.2 else {axis=2;return}
                    axis=1;origin=reveal;dragging=origin
                    withAnimation(motion) {revealedID=id}
                }
                guard axis==1 else {return}
                dragging=min(revealWidth,max(0,origin-value.translation.width))
            }.onEnded {value in
                defer {axis=0}
                ignoreTapUntil=Date().addingTimeInterval(0.3)
                guard axis==1,!locked else {return}
                let current=reveal,predicted=origin-value.predictedEndTranslation.width
                withAnimation(motion) {
                    revealedID=current>revealWidth*0.35 || (predicted>revealWidth*0.65 && current>0) ? id : nil
                    dragging=nil
                }
            }
    }
}
