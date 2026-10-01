import SwiftUI

/// Messages and discovery share the same typography, hit area and outer geometry.
struct CatalogSearchField: View {
    let placeholder: String
    @Binding var text: String
    let identifier: String
    let clearIdentifier: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing:10) {
            Image(systemName:"magnifyingglass").font(.system(size:14)).foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            TextField(LocalizedStringKey(placeholder),text:$text).font(.system(size:14)).focused($focused)
                .submitLabel(.search).onSubmit { focused = false }
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName:"xmark.circle.fill").font(.system(size:14))
                        .foregroundStyle(Theme.secondary).frame(width:30,height:40)
                }.buttonStyle(.plain).accessibilityLabel("清除搜索").accessibilityIdentifier(clearIdentifier)
            }
        }.padding(.horizontal,13).frame(height:44)
            .background(Theme.surface,in:RoundedRectangle(cornerRadius:14,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Theme.line.opacity(0.3),lineWidth:0.5))
            .accessibilityElement(children:.contain).accessibilityIdentifier("searchContainer-"+identifier)
    }
}
