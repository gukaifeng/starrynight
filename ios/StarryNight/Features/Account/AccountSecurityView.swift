import SwiftUI

struct AccountSecurityView:View {
    let account:AccountStore
    var onDeleted:()->Void
    @State private var username=""
    @State private var password=""
    @State private var newPassword=""
    @State private var busy=false
    @State private var notice:String?
    @State private var error:String?
    @State private var confirmDelete=false
    var body:some View {
        Form {
            Section {
                TextField("登录账号",text:$username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("当前密码",text:$password).textContentType(.password)
                Button("修改登录账号") {perform("username",["username":.string(username),"password":.string(password),"expected_version":.number(Double(account.cloudSession?.user.version ?? 0))])}
                    .disabled(busy || password.isEmpty || username.count<3)
                SecureField("新密码（至少 12 位）",text:$newPassword).textContentType(.newPassword)
                Button("修改密码") {perform("password",["current_password":.string(password),"new_password":.string(newPassword)])}
                    .disabled(busy || password.isEmpty || newPassword.count<12)
            } header:{Text("登录信息")} footer:{Text("修改账号或密码后，其他设备需要重新登录；星夜号与全部资料保持不变。")}.listRowBackground(Theme.surface)
            Section("登录保护") {
                Button("退出其他设备") {perform("sessions/revoke",["password":.string(password)])}.disabled(busy || password.isEmpty)
                Text("需要填写当前密码验证身份。本设备会获得新的登录凭证。")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }.listRowBackground(Theme.surface)
            if let notice {Section {Text(notice).foregroundStyle(Theme.accent)}.listRowBackground(Theme.surface)}
            if let error {Section {Text(error).foregroundStyle(Theme.peach)}.listRowBackground(Theme.surface)}
            Section {
                Button("注销账户",role:.destructive) {confirmDelete=true}.disabled(busy || password.isEmpty)
            } footer:{Text("账户注销会删除云端账户资料、角色订阅及平台保存的对话。此操作无法撤销。")}.listRowBackground(Theme.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("账户安全").navigationBarTitleDisplayMode(.inline)
            .onAppear {username=account.cloudSession?.user.username ?? ""}
            .confirmationDialog("确认永久注销账户？",isPresented:$confirmDelete,titleVisibility:.visible) {
                Button("永久注销",role:.destructive){deleteAccount()};Button("取消",role:.cancel){}
            } message:{Text("请先导出需要保留的资料。注销后无法恢复。")}
    }
    private func perform(_ action:String,_ fields:[String:JSONValue]) {
        busy=true;error=nil;notice=nil
        Task {@MainActor in
            defer {busy=false}
            do {try await account.updateCredentials(action,fields:fields);notice="已更新账户安全设置";password="";newPassword=""}
            catch is CancellationError {} catch {self.error=error.localizedDescription}
        }
    }
    private func deleteAccount() {
        guard let remote=account.cloudSession else{return};busy=true;error=nil
        Task {@MainActor in
            defer {busy=false}
            do {_ = try await PlatformAPI.shared.request("DELETE","/v1/me",token:remote.token,body:.object(["password":.string(password),"confirmation":.string("DELETE")]))
                guard account.cloudSession?.user.id==remote.user.id else{return};onDeleted()
            } catch {self.error=error.localizedDescription}
        }
    }
}
