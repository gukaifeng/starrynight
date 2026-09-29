import SwiftUI

struct AccountView: View {
    let account: AccountStore
    var onSignOut: () -> Void
    var embedded = false

    var body: some View {
        Group {
            if embedded { content }
            else {
                NavigationStack {
                    content.navigationTitle("账户").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeAccountButton") } }
                }
            }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
    }
    private var content: some View {
        List {
            Section {
                HStack(spacing:14) {
                    UserAccountAvatar(size:56)
                    VStack(alignment:.leading,spacing:6) {
                        Text(DemoAccount.name + (account.session?.accountID == DemoAccount.alternateID ? " B" : " A"))
                            .font(.headline)
                        Text("已登录 · 本机测试账户")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.vertical,6)
                .listRowSeparator(.hidden)
            }
            .listRowBackground(Theme.surface)
            .listRowInsets(EdgeInsets(top:10,leading:16,bottom:10,trailing:16))

            Section {
                accountRow("星夜号",value:account.session?.accountID ?? DemoAccount.id,identifier:"accountID")
                if let session = account.session {
                    accountRow("本次登录",value:session.method.title,identifier:"accountLoginMethod")
                }
            } header: {
                Text("账户信息").font(.footnote).foregroundStyle(Theme.secondary)
            }
            .listRowBackground(Theme.surface)
            .listRowInsets(EdgeInsets(top:10,leading:16,bottom:10,trailing:16))

            Section {
                ForEach(LoginMethod.allCases) { method in
                    LabeledContent {
                        Text(detail(method)).foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.trailing).fixedSize(horizontal:false,vertical:true)
                    } label: {
                        HStack(spacing:12) {
                            Image(systemName:method.symbol).font(.system(size:17,weight:.regular))
                                .foregroundStyle(Theme.accent.opacity(0.85)).frame(width:22).accessibilityHidden(true)
                            Text(method.title)
                        }
                    }
                    .font(.subheadline).frame(minHeight:32)
                    .accessibilityElement(children:.combine).accessibilityIdentifier("accountLink-"+method.rawValue)
                }
            } header: {
                Text("登录方式").font(.footnote).foregroundStyle(Theme.secondary)
            } footer: {
                Text("当前为本机测试账户，以上绑定信息仅供体验。")
                    .foregroundStyle(Theme.secondary)
            }
            .listRowBackground(Theme.surface)
            .listRowInsets(EdgeInsets(top:10,leading:16,bottom:10,trailing:16))

            Section {
                Button(action:onSignOut) {
                    Text("退出登录").font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex:0xF2A09D))
                        .frame(maxWidth:.infinity,minHeight:32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("signOutButton")
            } footer: {
                Text("退出后，本机的角色和聊天记录会保留。")
                    .foregroundStyle(Theme.secondary)
            }
            .listRowBackground(Theme.surface)
            .listRowInsets(EdgeInsets(top:10,leading:16,bottom:10,trailing:16))
        }
        .listStyle(.insetGrouped).listSectionSpacing(16)
        .contentMargins(.top,12,for:.scrollContent)
        .listRowSeparatorTint(Theme.line.opacity(0.55))
        .textCase(nil).scrollIndicators(.hidden).scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .softNavigationBackground()
    }

    private func accountRow(_ title:String,value:String,identifier:String) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(Theme.secondary).accessibilityIdentifier(identifier)
        } label: {
            Text(title)
        }
        .font(.subheadline).frame(minHeight:32)
    }
    private func detail(_ method:LoginMethod) -> String {
        switch method { case .wechat: "星夜体验微信"; case .email: DemoAccount.email; case .phone: "+86 138 **** 0000" }
    }
}

struct UserAccountAvatar: View {
    var size:CGFloat
    var signed = true
    var body:some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[Theme.card,Theme.background],startPoint:.topLeading,endPoint:.bottomTrailing))
            Image(systemName:signed ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size:size * 0.63,weight:.ultraLight)).foregroundStyle(Theme.accent.opacity(0.85))
        }
        .frame(width:size,height:size)
        .overlay(Circle().stroke(Theme.accent.opacity(0.25),lineWidth:1))
        .accessibilityHidden(true)
    }
}
