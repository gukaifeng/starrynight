import SwiftUI

struct DemoLoginView: View {
    @Bindable var account: AccountStore
    @State private var method = LoginMethod.wechat
    @State private var email = DemoAccount.email
    @State private var phone = DemoAccount.phone
    @State private var code = DemoAccount.code
    @State private var codeNotice = false
    @FocusState private var focused: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo:.largeTitle) private var titleSize = 31
    private enum Field { case identifier, code }
    private var motion: Animation { reduceMotion ? .easeInOut(duration:0.18) : .spring(response:0.4,dampingFraction:0.92) }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 680
            let compact = geometry.size.height < 500
            ScrollView {
                VStack(spacing:compact ? 14 : wide ? 40 : 18) {
                    HStack {
                        BrandSignature(size:38)
                        Spacer()
                        Text("本地测试版").font(.caption.weight(.medium)).padding(.horizontal,12).padding(.vertical,8)
                            .background(Theme.jade.opacity(0.5),in:Capsule()).accessibilityIdentifier("demoLoginBadge")
                    }
                    if wide {
                        HStack(alignment:.center,spacing:compact ? 28 : 64) {
                            welcome(wide:!compact).frame(maxWidth:.infinity)
                            loginForm.frame(width:compact ? 340 : 400)
                        }.frame(maxHeight:.infinity)
                    } else {
                        welcome(wide:false)
                        loginForm
                    }
                    Text("三种登录方式，同一个星夜账号。")
                        .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        .padding(.top,wide ? 20 : 0)
                }
                .padding(.horizontal,compact ? 24 : wide ? 48 : 24).padding(.vertical,18)
                .frame(maxWidth:1080).frame(minHeight:geometry.size.height).frame(maxWidth:.infinity)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .background(LinearGradient(colors:[Theme.card,Theme.background,Theme.jade.opacity(0.22)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea())
        }
        .foregroundStyle(Theme.ink).tint(Theme.accent)
        .animation(motion,value:method)
        .animation(motion,value:account.error)
        .animation(motion,value:codeNotice)
        .onChange(of:method) { _, _ in focused = nil; account.error = nil; codeNotice = false }
        .toolbar {
            ToolbarItemGroup(placement:.keyboard) {
                Spacer(); Button("完成输入") { focused = nil }.accessibilityIdentifier("finishLoginInput")
            }
        }
        .accessibilityIdentifier("loginPage")
    }

    @ViewBuilder private func welcome(wide:Bool) -> some View {
        if wide {
            VStack(spacing:24) {
                brandPortrait(size:164)
                welcomeTitle
                Text("让每一次相见，都接着上一次的温暖。")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }.multilineTextAlignment(.center).padding(.vertical,30)
        } else {
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:22) { brandPortrait(size:84); welcomeTitle }
                Text("让每一次相见，都接着上一次的温暖。")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private var welcomeTitle: some View {
        Text("一份陪伴，\n从这里开始。")
            .font(.system(size:titleSize,weight:.medium,design:.rounded)).lineSpacing(4)
            .fixedSize(horizontal:false,vertical:true)
    }
    private func brandPortrait(size:CGFloat) -> some View {
        Image("BrandMark").resizable().scaledToFit().frame(width:size,height:size)
            .clipShape(.rect(cornerRadius:size*0.26))
            .shadow(color:Theme.ink.opacity(0.1),radius:20,y:10).accessibilityHidden(true)
    }

    private var loginForm: some View {
        VStack(spacing:14) {
            HStack(spacing:6) {
                ForEach(LoginMethod.allCases) { option in
                    Button { method = option } label: {
                        Label(option.title,systemImage:option.symbol).font(.subheadline.weight(.semibold))
                            .frame(maxWidth:.infinity,minHeight:46)
                            .background(method == option ? Theme.ink : .clear,in:Capsule())
                            .foregroundStyle(method == option ? Theme.background : Theme.secondary)
                    }.buttonStyle(.plain).accessibilityIdentifier("loginMethod-"+option.rawValue)
                        .accessibilityAddTraits(method == option ? .isSelected : [])
                }
            }.padding(5).background(Theme.surface.opacity(0.68),in:Capsule())
            VStack(alignment:.leading,spacing:16) {
                if method == .wechat {
                    VStack(alignment:.leading,spacing:16) {
                        Label("微信快捷登录",systemImage:LoginMethod.wechat.symbol).font(.headline)
                        HStack(spacing:12) {
                            Image("BrandMark").resizable().scaledToFit().frame(width:48,height:48).clipShape(.rect(cornerRadius:14)).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:4) {
                                Text(DemoAccount.name).font(.subheadline.weight(.semibold))
                                Text("已准备好体验账号").font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength:0)
                            Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityHidden(true)
                        }
                        Text("本次使用测试身份，不会打开微信或请求授权。")
                            .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
                    }.transition(.opacity)
                } else {
                    credentialFields.transition(.opacity)
                }
            }
            .frame(maxWidth:.infinity,minHeight:142,alignment:.topLeading)
            .padding(18).background(Theme.surface.opacity(0.7),in:RoundedRectangle(cornerRadius:26))
            if let error = account.error {
                Label(error,systemImage:"info.circle").font(.caption).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    .accessibilityIdentifier("loginError").transition(.opacity)
            }
            Button(action:signIn) {
                HStack {
                    Text(method == .wechat ? "微信一键登录" : "登录，去见我的伙伴").font(.headline)
                    Spacer(); Image(systemName:"arrow.right")
                }.padding(.horizontal,22).frame(maxWidth:.infinity,minHeight:54)
                    .background(Theme.accent,in:Capsule()).foregroundStyle(Theme.background)
            }.buttonStyle(.plain).accessibilityIdentifier("signInButton")
            VStack(spacing:5) {
                Text("测试信息已填好，直接登录即可。")
                Text("无需真实账号，不会发送短信或邮件。")
            }.font(.caption).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
    }

    private var credentialFields: some View {
        VStack(alignment:.leading,spacing:14) {
            VStack(alignment:.leading,spacing:6) {
                Text(method == .email ? "邮箱地址" : "手机号码").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                HStack(spacing:9) {
                    if method == .phone { Text("+86").font(.subheadline).foregroundStyle(Theme.secondary) }
                    if method == .email {
                        TextField("邮箱地址",text:$email).keyboardType(.emailAddress).textContentType(.emailAddress)
                            .focused($focused,equals:.identifier).accessibilityLabel("邮箱地址").accessibilityIdentifier("loginEmail")
                    } else {
                        TextField("手机号码",text:$phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .focused($focused,equals:.identifier).accessibilityLabel("手机号码").accessibilityIdentifier("loginPhone")
                    }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal,12).frame(minHeight:46).background(Theme.background,in:RoundedRectangle(cornerRadius:13))
            }
            VStack(alignment:.leading,spacing:6) {
                Text("验证码").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                HStack(spacing:8) {
                    TextField("6位测试验证码",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .focused($focused,equals:.code).accessibilityLabel("验证码").accessibilityIdentifier("loginCode")
                        .padding(.horizontal,12).frame(minHeight:46).background(Theme.background,in:RoundedRectangle(cornerRadius:13))
                    Button("获取验证码") { code = DemoAccount.code; codeNotice = true; focused = nil; account.error = nil }
                        .font(.caption.weight(.semibold)).frame(minHeight:46).accessibilityIdentifier("requestLoginCode")
                }
            }
            HStack(alignment:.top,spacing:8) {
                Text(codeNotice ? "测试验证码已填入，没有发送短信或邮件。" : "体验账号 · 验证码123456")
                    .font(.caption2).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier("loginCodeHint")
                Spacer(minLength:0)
                Button("恢复测试信息") { restoreFixtures() }.font(.caption2.weight(.semibold))
                    .accessibilityIdentifier("restoreLoginFixtures")
            }
        }
    }
    private func restoreFixtures() {
        focused = nil; email = DemoAccount.email; phone = DemoAccount.phone; code = DemoAccount.code
        account.error = nil; codeNotice = false
    }
    private func signIn() {
        focused = nil
        account.signIn(method,identifier:method == .email ? email : phone,code:code)
    }
}
