import SwiftUI

struct CharacterMarketControls:View {
    let model:ModelDescriptor
    @Bindable var assets:CharacterAssetLibrary
    let accountID:String
    var onLogin:(()->Void)? = nil
    var onEnter:()->Void
    @State private var confirmDownload=false
    @State private var visible=false
    private var listing:CharacterStoreListing? {assets.listing(model.runtimeID)}
    private var size:String {ByteCountFormatter.string(fromByteCount:listing?.downloadBytes ?? 0,countStyle:.file)}
    private var needsAuthentication:Bool {PlatformAPI.shared.activeSession?.user.id != accountID}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:10) {
                Button {Task {await assets.audition(model.runtimeID)}} label: {
                    HStack(spacing:7) {
                        Image(systemName:assets.auditionID==model.runtimeID ? "stop.fill" : "play.fill").font(.system(size:10))
                        Text("听听她的声音").font(.system(size:12,weight:.medium))
                    }.padding(.horizontal,13).frame(height:35).background(Theme.card,in:Capsule())
                }.buttonStyle(.plain).disabled(listing?.media["audition"]?.url==nil).accessibilityIdentifier("marketAudition-"+model.id)
                Spacer()
                Text(assets.requiresDownload(model.runtimeID) ? "按需下载 · "+size : "已随 App 就绪")
                    .font(.system(size:10)).foregroundStyle(Theme.secondary)
            }
            switch assets.phase(model.runtimeID) {
            case .downloading(let progress,let label):
                VStack(spacing:8) {
                    ProgressView(value:progress).tint(Theme.accent)
                    HStack {Text(label+" · \(Int(progress*100))%");Spacer();Button("取消"){assets.cancel(model.runtimeID)}}.font(.system(size:11))
                    Text("校验通过后才会进入会话，当前聊天和记忆会保留。").font(.system(size:10)).foregroundStyle(Theme.secondary)
                }.accessibilityIdentifier("characterDownloadProgress")
            case .failed(let message):
                Text(LocalizedStringKey(message)).font(.system(size:11)).foregroundStyle(Theme.peach)
                action("重新下载",download:true)
            case .missing:action("下载角色，开始相处",download:true)
            case .ready:action("进入会话",download:false)
            }
        }.padding(14).background(Theme.surface.opacity(0.7),in:RoundedRectangle(cornerRadius:16))
            .background {
                CharacterDownloadConfirmationPresenter(isPresented:$confirmDownload,name:model.name,size:size,onDownload:startDownload)
                    .frame(width:0,height:0).accessibilityHidden(true)
            }
            .onAppear {visible=true}
            .onDisappear {visible=false;assets.stopAudition()}
    }
    private func action(_ label:String,download:Bool)->some View {
        Button {if download && needsAuthentication,let onLogin{onLogin()}else if download{confirmDownload=true}else{assets.stopAudition();onEnter()}} label: {
            HStack {Text(LocalizedStringKey(download && needsAuthentication ? "登录后下载角色" : label));Spacer();Image(systemName:download ? "arrow.down" : "arrow.up.right").font(.system(size:12))}.frame(maxWidth:.infinity)
        }.buttonStyle(NightPrimaryButton()).accessibilityIdentifier(download ? "downloadCharacter-"+model.id : "profileChatButton")
    }
    private func startDownload() {
        Task { @MainActor in
            do {_ = try await assets.download(model.runtimeID,accountID:accountID);assets.stopAudition();if visible{onEnter()}}
            catch { /* Retained in the download card with an explicit retry. */ }
        }
    }
}
struct CharacterDownloadPanel:View {
    @Bindable var coordinator:ViewerCoordinator
    let model:ModelDescriptor
    var body:some View {
        VStack(spacing:16) {
            PanelPageHeader("把她带到身边",backID:"closeCharacterDownload")
            CharacterCover(model:model,focalCrop:true).frame(height:190).clipShape(RoundedRectangle(cornerRadius:18))
            Text(model.name).font(.system(size:20,weight:.semibold,design:.rounded))
            CharacterMarketControls(model:model,assets:coordinator.assets,accountID:coordinator.library.accountID,onLogin:{
                coordinator.downloadPromptID=nil
                DispatchQueue.main.asyncAfter(deadline:.now()+0.35){coordinator.requestLogin()}
            }) {
                coordinator.downloadPromptID=nil;coordinator.openCharacter(model.id)
            }
            Spacer(minLength:0)
        }.padding(.horizontal,20).softSheetSurface().task {await coordinator.assets.refresh()}
    }
}
