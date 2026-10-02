import SwiftUI

/// Translation is a reading aid. Sending always uses the original choice and
/// keeps its already prepared answer branch intact.
struct SuggestionTranslationRow:View {
    let session:CompanionSession
    let option:AIQuickReply
    let index:Int
    let selected:()->Void
    @State private var translated:String?
    @State private var showing=false
    @State private var pending=false
    @State private var failed=false
    @State private var request:Task<Void,Never>?
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var language:AppLanguage {AppLanguage.resolve(locale.identifier,preferredLanguages:[locale.identifier])}
    var body:some View {
        HStack(spacing:2) {
            Button(action:selected) {
                HStack(spacing:7) {
                    Text(showing ? translated ?? option.text : option.text).font(.system(size:12)).lineLimit(3).multilineTextAlignment(.leading)
                    Spacer(minLength:2)
                    Image(systemName:"arrow.up.right").font(.system(size:9,weight:.medium)).foregroundStyle(Theme.secondary.opacity(0.7))
                }.padding(.leading,9).padding(.trailing,5).padding(.vertical,6).frame(maxWidth:.infinity,minHeight:34,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(ReplySuggestionPressStyle(reduceMotion:reduceMotion)).accessibilityLabel(showing ? translated ?? option.text : option.text)
                .accessibilityIdentifier("smartReplyOption-\(index)")
            if ReplyTranslation.needed([.init(id:"option",kind:"dialogue",text:option.text)],target:language) {
                Button(action:toggle) {
                    Group {if pending {ProgressView().controlSize(.mini)} else {Image(systemName:failed ? "arrow.clockwise" : showing ? "arrow.uturn.backward" : "translate").font(.system(size:10,weight:.medium))}}
                        .foregroundStyle(Theme.secondary.opacity(0.85)).frame(width:30,height:34).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(pending).accessibilityLabel(showing ? "原文" : failed ? "重试翻译" : "翻译")
                    .accessibilityIdentifier("translateSuggestion-"+option.id)
            }
        }.onChange(of:language) {request?.cancel();translated=nil;showing=false;pending=false;failed=false}
            .onDisappear {request?.cancel();pending=false}
    }
    private func toggle() {
        if showing {showing=false;return}
        if translated != nil {showing=true;return}
        pending=true;failed=false
        let target=language
        request=Task { @MainActor in
            defer {pending=false;request=nil}
            do {let value=try await session.translateSuggestion(option,to:target);try Task.checkCancellation();translated=value;withAnimation(.easeInOut(duration:0.18)){showing=true}}
            catch is CancellationError {} catch {failed=true}
        }
    }
}
