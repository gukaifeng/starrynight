import SwiftUI

struct AccountView: View {
    let account: AccountStore
    var onSignOut: () -> Void
    var embedded = false
    @State private var connecting = false

    var body: some View {
        Group {
            if connecting {
                VStack(alignment:.leading,spacing:0) {
                    Button { withAnimation(.easeInOut(duration:0.24)) { connecting = false } } label: {
                        Label("账户",systemImage:"chevron.left").font(.system(size:14)).padding(20)
                    }.buttonStyle(.plain)
                    LoginView(account:account).environment(\.softPanelDismiss,{ connecting = false })
                }.transition(.opacity)
            } else if embedded { content }
            else {
                NavigationStack {
                    content.navigationTitle("账户").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.topBarLeading) { PanelBackButton(identifier:"closeAccountButton") } }
                }
            }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softSheetSurface()
            .animation(.easeInOut(duration:0.24),value:connecting)
            .onChange(of:account.cloudSession) { _,value in if value != nil { connecting = false } }
    }
    private var content: some View {
        List {
            Section {
                HStack(spacing:14) {
                    UserAccountAvatar(size:56)
                    VStack(alignment:.leading,spacing:6) {
                        Text(account.cloudSession?.user.displayName ?? (DemoAccount.name + (account.session?.accountID == DemoAccount.alternateID ? " B" : " A")))
                            .font(.headline)
                        Text(account.cloudSession.map { $0.user.guest ? "测试体验 · 可注册保留资料" : "已连接账户服务" } ?? "本机体验账户")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.vertical,6)
                .listRowSeparator(.hidden)
            }
            .listRowBackground(Theme.surface)
            .listRowInsets(EdgeInsets(top:10,leading:16,bottom:10,trailing:16))

            if let cloud = account.cloudSession {
                Section {
                    if !cloud.user.guest { accountRow("账号",value:cloud.user.username,identifier:"serverUsername") }
                    accountRow("资料同步",value:account.syncStatus,identifier:"accountSyncStatus")
                    Button("立即同步") { account.onSync?() }.accessibilityIdentifier("syncAccountNow")
                    if account.needsReauthentication && !cloud.user.guest {
                        Button("重新登录") { connecting = true }.accessibilityIdentifier("reauthenticateAccount")
                    }
                    if account.hasSyncConflicts {
                        Button("保留本机副本，采用云端版本") { account.onUseCloud?() }.font(.footnote)
                    }
                    if cloud.user.guest { Button("设置账号与密码") { connecting = true }.accessibilityIdentifier("upgradeGuestAccount") }
                } header: { Text("账户与资料") }
                    .listRowBackground(Theme.surface)
            } else {
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
                Button("连接服务端账户") { connecting = true }.accessibilityIdentifier("connectPlatformAccount")
            }.listRowBackground(Theme.surface)
            }

            if account.cloudSession == nil {
            Section {
                ForEach(LoginMethod.allCases) { method in
                    LabeledContent {
                        Text(detail(method)).foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.trailing).fixedSize(horizontal:false,vertical:true)
                    } label: {
                        HStack(spacing:12) {
                            Image(systemName:method.symbol).font(.system(size:17,weight:.regular))
                                .foregroundStyle(Theme.accent.opacity(0.85)).frame(width:22).accessibilityHidden(true)
                            Text(LocalizedStringKey(method.title))
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
            }

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
            Text(LocalizedStringKey(title))
        }
        .font(.subheadline).frame(minHeight:32)
    }
    private func detail(_ method:LoginMethod) -> String {
        switch method { case .wechat: "星夜体验微信"; case .email: DemoAccount.email; case .phone: "+86 138 **** 0000";case .password:"账号密码";case .testGuest:"测试体验" }
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
