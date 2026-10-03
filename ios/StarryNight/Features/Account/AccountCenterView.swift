import SwiftUI

struct AccountCenterView: View {
    let account: AccountStore
    var onSignOut: () -> Void
    @State private var page = "account"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                Picker("我的",selection:$page) {
                    Text("账号").tag("account")
                    Text("关于星夜").tag("about")
                }.pickerStyle(.segmented).padding(.horizontal,24).padding(.vertical,12)
                    .accessibilityIdentifier("accountCenterTabs")
                Group {
                    if page == "account" { AccountView(account:account,onSignOut:onSignOut,embedded:true) }
                    else { AboutView(embedded:true) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity).transition(.opacity)
            }.softNavigationBackground().navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeAccountCenterButton") } }
                .animation(.easeInOut(duration:reduceMotion ? 0.18 : 0.25),value:page)
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
    }
}
