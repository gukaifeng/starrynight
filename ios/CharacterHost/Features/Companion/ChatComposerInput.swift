import SwiftUI
import UIKit

/// A wrapping chat input with a real Send action. SwiftUI's vertical TextField
/// changes the Return key's label, but still consumes Return as a line break.
struct ChatComposerInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var fontSize: CGFloat
    var foreground: UIColor
    var accent: UIColor
    var maxLines: Int
    var isEnabled: Bool
    var onSend: () -> Void
    var identifier:String="chatInput"

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ChatComposerTextView { context.coordinator.makeTextView() }
    func updateUIView(_ view: ChatComposerTextView, context: Context) {
        context.coordinator.input = self
        context.coordinator.update(view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChatComposerTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let line = uiView.font?.lineHeight ?? fontSize
        let lines = max(1, maxLines)
        let height = uiView.sizeThatFits(CGSize(width:width, height:.greatestFiniteMagnitude)).height
        return CGSize(width:width, height:ceil(min(max(line,height), line * CGFloat(lines) + 3 * CGFloat(lines-1))))
    }
    static func dismantleUIView(_ view: ChatComposerTextView, coordinator: Coordinator) {
        view.delegate = nil; view.pasteDelegate = nil
        view.wantsFocus = false; view.resignFirstResponder()
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var input: ChatComposerInput
        private var updating = false
        init(_ input: ChatComposerInput) { self.input = input }

        func makeTextView() -> ChatComposerTextView {
            let view = ChatComposerTextView()
            view.delegate = self; view.pasteDelegate = self
            view.backgroundColor = .clear
            view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
            view.isScrollEnabled = true; view.showsVerticalScrollIndicator = false
            view.showsHorizontalScrollIndicator = false
            view.contentInsetAdjustmentBehavior = .never
            view.returnKeyType = .send; view.enablesReturnKeyAutomatically = true
            view.allowsEditingTextAttributes = false
            view.accessibilityIdentifier = input.identifier
            view.accessibilityLabel = "想和你说…"
            view.setContentHuggingPriority(.defaultLow, for:.horizontal)
            view.setContentCompressionResistancePriority(.defaultLow, for:.horizontal)
            update(view)
            return view
        }
        func update(_ view: ChatComposerTextView) {
            updating = true; defer { updating = false }
            // Never replace marked text while a Chinese/Japanese IME is composing.
            if view.markedTextRange == nil {
                let font = UIFont.systemFont(ofSize:input.fontSize)
                if view.font != font || view.textColor != input.foreground {
                    view.font = font; view.textColor = input.foreground
                    let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
                    let attributes: [NSAttributedString.Key:Any] = [
                        .font:font, .foregroundColor:input.foreground, .paragraphStyle:paragraph
                    ]
                    view.typingAttributes = attributes
                    view.textStorage.addAttributes(attributes, range:NSRange(location:0,length:view.textStorage.length))
                }
                if view.text != input.text { replaceText(in:view, with:input.text) }
            }
            view.tintColor = input.accent
            view.isEditable = input.isEnabled; view.isUserInteractionEnabled = input.isEnabled
            view.wantsFocus = input.isFocused && input.isEnabled
            view.synchronizeFocus()
            // Ending editing may commit marked text. A draft cleared by the
            // send button must also clear that now-committed native content.
            if view.markedTextRange == nil, view.text != input.text { replaceText(in:view, with:input.text) }
        }
        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !updating else { return }
            if !input.isFocused { input.isFocused = true }
            (textView as? ChatComposerTextView)?.wantsFocus = true
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            guard !updating else { return }
            publishText(textView)
            if input.isFocused { input.isFocused = false }
            (textView as? ChatComposerTextView)?.wantsFocus = false
        }
        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            publishText(textView)
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" || text == "\r" || text == "\r\n" else { return true }
            guard textView.markedTextRange == nil,
                  (textView as? ChatComposerTextView)?.insertingLiteralText != true else { return true }
            // Consume Return even for whitespace-only drafts; it must not grow the
            // input or dismiss the keyboard. The same send() handles valid drafts.
            guard input.isEnabled else { return false }
            publishText(textView)
            if !input.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                input.onSend()
                // Reflect the cleared/retained draft immediately, before another
                // Return event can arrive ahead of SwiftUI's next update.
                if textView.text != input.text { replaceText(in:textView, with:input.text) }
            }
            return false
        }
        func textPasteConfigurationSupporting(_ supporting: UITextPasteConfigurationSupporting,
                                             performPasteOf attributedString: NSAttributedString,
                                             to textRange: UITextRange) -> UITextRange {
            guard input.isEnabled, let view = supporting as? ChatComposerTextView, view.isEditable else { return textRange }
            // Paste/drop is delivered asynchronously by UIKit. Handle its final
            // insertion so even a clipboard containing only "\n" cannot send.
            let start = view.offset(from:view.beginningOfDocument, to:textRange.start)
            view.insertingLiteralText = true
            defer { view.insertingLiteralText = false }
            view.replace(textRange, withText:attributedString.string)
            publishText(view)
            let end = min(start + attributedString.string.utf16.count, view.text.utf16.count)
            guard let first = view.position(from:view.beginningOfDocument, offset:min(start,end)),
                  let last = view.position(from:view.beginningOfDocument, offset:end),
                  let inserted = view.textRange(from:first,to:last) else { return textRange }
            return inserted
        }
        private func publishText(_ view: UITextView) {
            let current = view.text ?? ""
            let committed = view.markedTextRange == nil ? String(current.prefix(500)) : current
            if committed != current { replaceText(in:view, with:committed) }
            if input.text != committed { input.text = committed }
            view.invalidateIntrinsicContentSize()
        }
        private func replaceText(in view: UITextView, with text: String) {
            let selection = view.selectedRange
            view.text = text
            let start = min(selection.location, text.utf16.count)
            view.selectedRange = NSRange(location:start,length:min(selection.length,text.utf16.count-start))
            if text.isEmpty { view.setContentOffset(.zero, animated:false) }
            view.invalidateIntrinsicContentSize()
        }
    }
}

final class ChatComposerTextView: UITextView {
    var insertingLiteralText = false
    var wantsFocus = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { synchronizeFocus() }
    }
    func synchronizeFocus() {
        if wantsFocus && !isFirstResponder && window != nil { becomeFirstResponder() }
        else if !wantsFocus && isFirstResponder { resignFirstResponder() }
    }
    override var keyCommands: [UIKeyCommand]? {
        let newline = UIKeyCommand(input:"\r", modifierFlags:.shift, action:#selector(insertLineBreak))
        newline.discoverabilityTitle = "换行"
        newline.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [newline]
    }
    @objc func insertLineBreak() {
        guard isEditable, markedTextRange == nil else { return }
        insertingLiteralText = true; defer { insertingLiteralText = false }
        insertText("\n")
    }
}
