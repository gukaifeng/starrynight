import SwiftUI

/// Own the reveal state instead of letting List's native swipe action collapse
/// immediately when Delete opens a confirmation alert. Vertical drags still
/// belong to the scroll view; direction is decided once per gesture.
struct ConversationSwipeRow<Content:View>:View {
    let id:String
    @Binding var revealedID:String?
    var locked:Bool
    var onOpen:()->Void
    var onHide:()->Void
    var onDelete:()->Void
    @ViewBuilder var content:()->Content
    @State private var side:CGFloat=1
    @State private var dragging:CGFloat?
    @State private var origin:CGFloat=0
    @State private var axis=0
    @State private var ignoreTapUntil=Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let revealWidth:CGFloat=144
    private var offset:CGFloat {dragging ?? (revealedID==id ? side*revealWidth : 0)}
    private var motion:Animation {.spring(response:reduceMotion ? 0.18 : 0.32,dampingFraction:0.92)}
    var body:some View {
        ZStack {
            if abs(offset)>0.1 {
            HStack(spacing:6) {
                Button(action:onHide) {Text("不显示").frame(maxWidth:.infinity,maxHeight:.infinity)}
                    .background(Theme.card,in:RoundedRectangle(cornerRadius:13))
                    .accessibilityIdentifier("hideConversation-"+id)
                Button(role:.destructive,action:onDelete) {Text("删除").frame(maxWidth:.infinity,maxHeight:.infinity)}
                    .background(Color(hex:0xAC3E4E),in:RoundedRectangle(cornerRadius:13))
                    .accessibilityIdentifier("deleteConversation-"+id)
            }.font(.system(size:12,weight:.medium)).foregroundStyle(.white).buttonStyle(.plain)
                .frame(width:revealWidth-8).padding(.vertical,5)
                .frame(maxWidth:.infinity,alignment:offset>=0 ? .leading : .trailing)
                .opacity(abs(offset)>0.1 ? 1 : 0).allowsHitTesting(abs(offset)>50 && !locked)
                .accessibilityHidden(abs(offset)<50)
                .mask(alignment:offset>=0 ? .leading : .trailing) {Rectangle().frame(width:abs(offset))}
                .zIndex(1)
            }
            Button {
                // A simultaneous drag can finish before Button releases its
                // tracking touch. That release must not close the revealed row.
                guard Date()>=ignoreTapUntil else {return}
                if revealedID==id {withAnimation(motion) {revealedID=nil}}
                else {onOpen()}
            } label: {content().frame(maxWidth:.infinity).background(Theme.background.opacity(abs(offset)>0.1 ? 1 : 0))}
                .buttonStyle(.plain).accessibilityIdentifier("message-"+id)
                .offset(x:offset).allowsHitTesting(!locked)
        }.clipped().contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance:12).onChanged {value in
                guard !locked else {return}
                if axis==0 {
                    guard abs(value.translation.width)>abs(value.translation.height)*1.2 else {axis=2;return}
                    axis=1;origin=offset;dragging=origin;revealedID=id
                }
                guard axis==1 else {return}
                ignoreTapUntil=Date().addingTimeInterval(0.3)
                dragging=min(revealWidth,max(-revealWidth,origin+value.translation.width))
            }.onEnded {value in
                defer {axis=0}
                guard axis==1,!locked else {return}
                ignoreTapUntil=Date().addingTimeInterval(0.3)
                let current=offset,predicted=origin+value.predictedEndTranslation.width
                withAnimation(motion) {
                    side=current>=0 ? 1 : -1
                    revealedID=abs(current)>revealWidth*0.35 || (abs(predicted)>revealWidth*0.65 && predicted*current>0) ? id : nil
                    dragging=nil
                }
            })
            .accessibilityAction(named:Text("不显示"),onHide)
            .accessibilityAction(named:Text("删除对话和记忆"),onDelete)
    }
}
