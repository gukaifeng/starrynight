import SwiftUI

struct ProfileHelpView:View {
    let account:AccountStore
    var body:some View {
        List {
            Section("开始相处") {
                Text("在发现页选择角色，查看资料后订阅。消息页可以查看你们的故事，再进入会话。")
                Text("角色头像旁可查看资料；右上角会话选项可调整取景、声音和氛围。")
                Text("不显示只隐藏消息条目。重置会清空该角色的对话和记忆，需要二次确认。")
            }.listRowBackground(Theme.surface)
            Section("账户与同步") {
                Text("登录后，订阅、关注、设置、对话与共同记忆跟随账户。星夜号永久不变，登录账号可以修改。")
                Text("微信、短信与邮箱验证仍在接入准备中，目前使用账号和密码登录。")
            }.listRowBackground(Theme.surface)
            Section {NavigationLink("意见反馈") {ProfileFeedbackView(account:account)}}.listRowBackground(Theme.surface)
        }.font(.subheadline).scrollContentBackground(.hidden).background(Theme.background).navigationTitle("帮助与反馈").navigationBarTitleDisplayMode(.inline)
    }
}

struct ProfileFeedbackView:View {
    let account:AccountStore
    @State private var category="suggestion"
    @State private var content=""
    @State private var sending=false
    @State private var receipt:String?
    @State private var error:String?
    var body:some View {
        Form {
            Section {
                Picker("类型",selection:$category) {Text("建议").tag("suggestion");Text("功能问题").tag("bug");Text("账户问题").tag("account");Text("内容问题").tag("content")}
                TextField("说说你的想法或遇到的问题",text:$content,axis:.vertical).lineLimit(5...8)
                Button {send()} label:{HStack {if sending {ProgressView()};Text("提交反馈")}}
                    .disabled(sending || content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || content.count>2000 || account.cloudSession==nil)
            } footer:{Text(account.cloudSession==nil ? "登录后可以提交反馈并保存处理记录。" : "反馈与当前账户关联，请勿填写密码或其他敏感凭证。")}.listRowBackground(Theme.surface)
            if let receipt {Section("已提交") {Text(receipt).font(.caption).textSelection(.enabled)}.listRowBackground(Theme.surface)}
            if let error {Section {Text(error).foregroundStyle(Theme.peach)}.listRowBackground(Theme.surface)}
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("意见反馈").navigationBarTitleDisplayMode(.inline)
    }
    private func send() {
        guard let remote=account.cloudSession else{return};sending=true;error=nil
        Task {@MainActor in
            defer {sending=false}
            do {let reply=try await PlatformAPI.shared.request("POST","/v1/me/feedback",token:remote.token,body:.object(["category":.string(category),"content":.string(content)]))
                guard account.cloudSession?.user.id==remote.user.id else{return}
                guard let id=reply.object?["id"]?.string,!id.isEmpty else {throw PlatformError.invalidResponse}
                receipt=id;content=""
            } catch {self.error=error.localizedDescription}
        }
    }
}

struct ProfilePrivacyView:View {
    let account:AccountStore
    @State private var exporting=false
    @State private var exportFile:URL?
    @State private var error:String?
    var body:some View {
        List {
            Section("资料与隐私") {
                Text("聊天、共同记忆、角色偏好与订阅按账户保存。麦克风仅在你启用语音输入时使用。")
                Text("角色回复与语音处理会通过云端 AI 服务完成。请勿把密码、验证码或需要保密的工作资料发送给角色。")
                Button("导出账户资料") {export()}.disabled(exporting || account.cloudSession==nil)
                if exporting {ProgressView("正在准备资料")}
                if let exportFile {ShareLink(item:exportFile) {Label("保存或分享资料文件",systemImage:"square.and.arrow.up")}}
                if let error {Text(error).foregroundStyle(Theme.peach)}
            }.listRowBackground(Theme.surface)
            Section("删除与保留") {
                Text("清理缓存不会删除聊天。单个角色可在消息资料卡中重置；账户注销入口在账户安全中。")
                Text("当前为开发测试版本。本页说明数据处理方式，正式发布前仍需完善隐私政策、用户协议与服务联系方式。")
            }.listRowBackground(Theme.surface)
        }.font(.subheadline).scrollContentBackground(.hidden).background(Theme.background).navigationTitle("隐私与数据").navigationBarTitleDisplayMode(.inline)
            .onDisappear {if let exportFile {try? FileManager.default.removeItem(at:exportFile)}}
    }
    private func export() {
        guard let remote=account.cloudSession else{return};exporting=true;error=nil
        if let exportFile {try? FileManager.default.removeItem(at:exportFile);self.exportFile=nil}
        Task {@MainActor in
            defer {exporting=false}
            do {
                let file=FileManager.default.temporaryDirectory.appendingPathComponent("StarryNight-Account-"+UUID().uuidString+".jsonl")
                FileManager.default.createFile(atPath:file.path,contents:nil,attributes:[.protectionKey:FileProtectionType.complete])
                let handle=try FileHandle(forWritingTo:file);defer {try? handle.close()}
                var completed=false;defer {if !completed {try? FileManager.default.removeItem(at:file)}}
                let encoder=JSONEncoder()
                try handle.write(contentsOf:encoder.encode(JSONValue.object(["schema_version":.number(1),"account_id":.string(remote.user.id)]))+Data([10]))
                var cursor="0";var seen=Set<String>()
                repeat {
                    guard seen.insert(cursor).inserted else {throw PlatformError.invalidResponse}
                    let page=try await PlatformAPI.shared.request("GET","/v1/me/export?after="+cursor+"&limit=200",token:remote.token)
                    guard account.cloudSession?.user.id==remote.user.id else {throw CancellationError()}
                    guard case .array(let values)?=page.object?["items"] else {throw PlatformError.invalidResponse}
                    for value in values {try handle.write(contentsOf:encoder.encode(value)+Data([10]))}
                    cursor=page.object?["next_cursor"]?.string ?? ""
                } while !cursor.isEmpty
                completed=true;exportFile=file
            } catch is CancellationError {} catch {self.error=error.localizedDescription}
        }
    }
}
