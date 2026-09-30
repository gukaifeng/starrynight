import SwiftUI
import UIKit

/// Uses the production UITextView and coordinator; never creates an AI session.
struct ChatComposerInputTests {
    @MainActor private final class Draft {
        var text = ""
        var focused = false
        var sent: [String] = []
    }
    @MainActor static func run() throws -> String {
        let draft = Draft()
        let input = ChatComposerInput(text:Binding(get:{ draft.text },set:{ draft.text = $0 }),
            isFocused:Binding(get:{ draft.focused },set:{ draft.focused = $0 }),
            fontSize:15,foreground:.white,accent:.cyan,maxLines:3,isEnabled:true,
            onSend:{ draft.sent.append(draft.text); draft.text = "" })
        let coordinator = input.makeCoordinator()
        let view = coordinator.makeTextView()
        view.frame = CGRect(x:0,y:0,width:240,height:80)
        var checks = 0
        func check(_ value:Bool,_ message:String) throws {
            guard value else { throw NSError(domain:"ChatComposerInput",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
            checks += 1
        }
        func setDraft(_ text:String) {
            draft.text = text; coordinator.update(view)
            view.selectedRange = NSRange(location:text.utf16.count,length:0)
        }
        func pressReturn(_ text:String = "\n") -> Bool {
            coordinator.textView(view,shouldChangeTextIn:view.selectedRange,replacementText:text)
        }
        try check(view.returnKeyType == .send,"Keyboard exposes Send")
        for lineBreak in ["\n","\r","\r\n"] {
            let text = "今晚一起看星星 \(draft.sent.count)"
            setDraft(text); let before = draft.sent.count
            try check(!pressReturn(lineBreak),"Keyboard Return must not insert a line break")
            try check(draft.sent.count == before+1 && draft.sent.last == text,"Return sends the current draft once")
            try check(view.text.isEmpty && draft.text.isEmpty,"Send clears native and bound drafts together")
            _ = pressReturn(lineBreak)
            try check(draft.sent.count == before+1,"A repeated Return cannot resend the stale native text")
        }
        setDraft(" \n \t")
        let before = draft.sent.count
        try check(!pressReturn() && draft.sent.count == before,"Whitespace does not send or add another line")
        try check(draft.text == " \n \t","Ignored Return preserves the whitespace draft")

        setDraft("我想说")
        view.setMarkedText("nihao",selectedRange:NSRange(location:5,length:0))
        try check(view.markedTextRange != nil,"The test must actually establish an IME marked range")
        coordinator.textViewDidChange(view)
        let composingText = view.text
        coordinator.update(view)
        try check(view.markedTextRange != nil && view.text == composingText,"SwiftUI updates preserve composition")
        try check(pressReturn() && draft.sent.count == before,"IME confirmation stays with the input method")
        view.unmarkText(); coordinator.textViewDidChange(view)

        // UIKit's final paste callback runs after item providers resolve. It must
        // not treat a single newline from the clipboard as a keyboard command.
        for pasted in ["\n", "第一行\n第二行", "🌙\n今晚好"] {
            setDraft("开头")
            _ = coordinator.textPasteConfigurationSupporting(view,
                performPasteOf:NSAttributedString(string:pasted),to:view.selectedTextRange!)
            try check(view.text == "开头"+pasted && draft.text == view.text,"Paste keeps literal multiline content")
            try check(draft.sent.count == before,"Paste never invokes Send")
        }
        setDraft("第一行")
        view.insertLineBreak()
        try check(view.text == "第一行\n" && draft.sent.count == before,"Shift-Return inserts a deliberate line break")
        try check(view.keyCommands?.contains(where:{ $0.modifierFlags == .shift && $0.input == "\r" }) == true,
                  "Hardware keyboard advertises Shift-Return")

        setDraft(String(repeating:"星",count:499))
        view.setMarkedText("nihao",selectedRange:NSRange(location:5,length:0))
        coordinator.textViewDidChange(view)
        try check(view.markedTextRange != nil && draft.text.count > 500,"Limit does not cut uncommitted IME text")
        view.unmarkText(); coordinator.textViewDidChange(view)
        try check(draft.text.count == 500 && view.text.count == 500,"Limit applies after composition commits")
        setDraft("")
        let emojiText = String(repeating:"星",count:499)+"👩🏽‍🚀"+"超出"
        _ = coordinator.textPasteConfigurationSupporting(view,
            performPasteOf:NSAttributedString(string:emojiText),to:view.selectedTextRange!)
        try check(draft.text.count == 500 && draft.text.hasSuffix("👩🏽‍🚀"),"Length limit preserves emoji grapheme clusters")

        setDraft("保留草稿")
        coordinator.textViewDidBeginEditing(view)
        try check(draft.focused,"UIKit focus reaches the chat's editing state")
        coordinator.textViewDidEndEditing(view)
        try check(!draft.focused && draft.text == "保留草稿","Outside dismissal ends focus and preserves the draft")
        coordinator.input.isEnabled = false; coordinator.update(view)
        try check(!view.isEditable && !pressReturn() && draft.sent.count == before,"Character editing disables keyboard submission")
        return "PASS: \(checks) native chat input, Send, IME, paste, repeat, length and focus checks"
    }
}
