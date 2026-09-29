import SwiftUI

private struct SoftPanelCloseKey: EnvironmentKey {
    static let defaultValue: SoftPanelCloseRequest? = nil
}
extension EnvironmentValues {
    var softPanelCloseRequest: SoftPanelCloseRequest? {
        get { self[SoftPanelCloseKey.self] }
        set { self[SoftPanelCloseKey.self] = newValue }
    }
}

struct PanelBackButton: View {
    var identifier: String
    @Environment(\.softPanelDismiss) private var dismiss
    var body: some View {
        Button(action:dismiss) {
            Image(systemName:"chevron.left").font(.body.weight(.semibold))
                .frame(minWidth:44,minHeight:44).contentShape(Rectangle())
        }.accessibilityLabel("返回").accessibilityHint("返回上一页")
            .accessibilityIdentifier(identifier)
    }
}

/// A panel keeps one header geometry while its content fades between pages.
/// Native navigation bars inside child pages otherwise add their own safe area.
struct PanelPageHeader<Trailing:View>: View {
    let title:String
    let subtitle:String?
    let backID:String
    let backAction:(() -> Void)?
    let trailing:Trailing
    init(_ title:String,subtitle:String? = nil,backID:String,backAction:(() -> Void)? = nil,
         @ViewBuilder trailing:() -> Trailing) {
        self.title=title;self.subtitle=subtitle;self.backID=backID;self.backAction=backAction;self.trailing=trailing()
    }
    var body:some View {
        HStack(spacing:10) {
            if let backAction {
                Button(action:backAction) {
                    Image(systemName:"chevron.left").font(.body.weight(.semibold))
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("返回").accessibilityIdentifier(backID)
            } else { PanelBackButton(identifier:backID).buttonStyle(.plain) }
            VStack(alignment:.leading,spacing:3) {
                Text(title).font(.system(size:16,weight:.medium)).lineLimit(1).minimumScaleFactor(0.8)
                if let subtitle { Text(subtitle).font(.system(size:11)).foregroundStyle(Theme.secondary).lineLimit(1) }
            }.frame(maxWidth:.infinity,alignment:.leading)
            trailing
        }.frame(height:44).padding(.horizontal,22).padding(.top,16).padding(.bottom,12)
            .foregroundStyle(Theme.ink).tint(Theme.accent)
    }
}
extension PanelPageHeader where Trailing == EmptyView {
    init(_ title:String,subtitle:String? = nil,backID:String,backAction:(() -> Void)? = nil) {
        self.init(title,subtitle:subtitle,backID:backID,backAction:backAction) { EmptyView() }
    }
}
