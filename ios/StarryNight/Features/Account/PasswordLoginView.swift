import SwiftUI

struct LoginView: View {
    @Bindable var account:AccountStore
    @State private var registering = false
    @State private var username = ""
    @State private var password = ""
    @State private var profileName = ""
    @State private var allowsGuest = false
    @FocusState private var focused:Bool
    @Environment(\.softPanelDismiss) private var close
    var body:some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--auth-testing") { DemoLoginView(account:account) }
        else { content }
#else
        content
#endif
    }
    private var content:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack { BrandSignature(size:34);Spacer() }
                VStack(alignment:.leading,spacing:9) {
                    Text(registering ? "把相遇，留在星夜。" : "回到熟悉的陪伴。")
                        .font(.system(size:27,weight:.medium,design:.rounded))
                    Text(registering ? "你的偏好、记忆和故事，跟着账户一起。" : "登录后，继续上一次的故事。")
                        .font(.system(size:13)).foregroundStyle(Theme.secondary)
                }
                Picker("账户",selection:$registering) { Text("登录").tag(false);Text("注册").tag(true) }
                    .pickerStyle(.segmented).accessibilityIdentifier("passwordAuthMode")
                VStack(spacing:14) {
                    if registering { field("昵称",text:$profileName,id:"registerNickname",type:.nickname) }
                    field("账号 · 字母、数字或下划线",text:$username,id:"passwordUsername",type:.username)
                    SecureField("密码 · 至少 12 位",text:$password)
                        .textContentType(registering ? .newPassword : .password).focused($focused)
                        .padding(16).background(Theme.surface.opacity(0.65),in:RoundedRectangle(cornerRadius:16))
                        .accessibilityIdentifier("passwordCredential")
                }.font(.system(size:15))
                if let error = account.error { Text(LocalizedStringKey(error)).font(.system(size:12)).foregroundStyle(Theme.peach).accessibilityIdentifier("loginError") }
                Button {
                    focused = false
                    Task { await account.authenticate(action:registering ? "register" : "login",username:username,password:password,name:profileName) }
                } label: {
                    HStack { Text(registering ? "创建账户" : "登录星夜");Spacer();if account.isBusy { ProgressView().tint(Theme.background) } else { Image(systemName:"arrow.right") } }
                        .font(.system(size:15,weight:.semibold)).padding(.horizontal,20).frame(height:50)
                        .background(Theme.gradient,in:Capsule()).foregroundStyle(Theme.background)
                }.buttonStyle(.plain).disabled(account.isBusy).accessibilityIdentifier("passwordSignIn")
                if allowsGuest {
                    Button("跳过登录，先体验") {
                        focused = false;Task { await account.authenticate(action:"guest") }
                    }.font(.system(size:13)).frame(maxWidth:.infinity,minHeight:44)
                        .disabled(account.isBusy).accessibilityIdentifier("serverGuestLogin")
                } else {
                    Button("暂不登录") { focused = false;close() }.font(.system(size:13)).frame(maxWidth:.infinity,minHeight:44)
                }
                HStack(spacing:20) {
                    Label("微信",systemImage:"bubble.left.and.bubble.right");Label("手机号",systemImage:"iphone")
                    Spacer();Text("即将支持")
                }.font(.system(size:11)).foregroundStyle(Theme.secondary.opacity(0.65))
            }.padding(24).padding(.top,14).frame(maxWidth:500).frame(maxWidth:.infinity)
        }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea()).foregroundStyle(Theme.ink).tint(Theme.accent)
            .animation(.easeInOut(duration:0.24),value:registering)
            .onChange(of:registering) { _,_ in account.error = nil }
            .task {
                if let saved=account.cloudSession,!saved.user.guest {username=saved.user.username}
                if account.cloudSession?.user.guest == true { registering = true }
                if let result = try? await PlatformAPI.shared.request("GET","/v1/capabilities") { allowsGuest = result.object?["test_guest"]?.bool == true && account.cloudSession == nil }
            }.accessibilityIdentifier("passwordLoginPage")
    }
    private func field(_ title:String,text:Binding<String>,id:String,type:UITextContentType) -> some View {
        TextField(title,text:text).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(type)
            .focused($focused).padding(16).background(Theme.surface.opacity(0.65),in:RoundedRectangle(cornerRadius:16))
            .accessibilityIdentifier(id)
    }
}
