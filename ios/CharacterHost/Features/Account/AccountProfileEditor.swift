import SwiftUI
import PhotosUI
import Photos

struct AccountProfileEditor:View {
    let account:AccountStore
    static let avatarSymbols=["moon.stars.fill","sparkles","sun.max.fill","leaf.fill","cat.fill","person.crop.circle.fill"]
    static let starryAvatars=["starry-orbit-v1"]
    @State private var name=""
    @State private var bio=""
    @State private var gender="unspecified"
    @State private var avatar="starry-orbit-v1"
    @State private var showingPhotos=false
    @State private var photoPermissionDenied=false
    @State private var selectedPhoto:PhotosPickerItem?
    @State private var photoData:Data?
    @State private var processing=false
    @State private var saving=false
    @State private var error:String?
    private struct Draft:Equatable {
        var name:String;var bio:String;var gender:String;var avatar:String;var photo:Data?
        var valid:Bool {!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.count<=48 && bio.count<=500}
    }
    @State private var savedDraft:Draft?
    @State private var uploadedPhoto:Data?
    @State private var editingOwner:String?
    @State private var debounceTask:Task<Void,Never>?
    private var draft:Draft {Draft(name:name,bio:bio,gender:gender,avatar:avatar,photo:photoData)}
    var body:some View {
        Form {
            Section {
                HStack {Spacer();UserAccountAvatar(size:72,symbol:avatar,preview:photoData.flatMap {UIImage(data:$0)});Spacer()}.listRowBackground(Color.clear)
                HStack(spacing:20) {ForEach(Self.starryAvatars,id:\.self) {choice in
                    Button {avatar=choice;photoData=nil;selectedPhoto=nil} label: {
                        StarryDefaultAvatar(kind:choice).frame(width:44,height:44).clipShape(Circle())
                            .overlay(Circle().stroke(Theme.accent.opacity(avatar==choice ? 0.9 : 0.08),lineWidth:2))
                    }.buttonStyle(.plain).accessibilityLabel("小星球")
                        .accessibilityIdentifier("avatar-"+choice)
                };Spacer(minLength:0)
                    Button {choosePhoto()} label: {Image(systemName:"photo.badge.plus").font(.system(size:20,weight:.light)).frame(width:44,height:44)}
                        .accessibilityLabel("从相册选择头像").accessibilityIdentifier("chooseAccountPhoto")
                }
                if processing {ProgressView("正在准备头像…")}
                TextField("昵称",text:$name).accessibilityIdentifier("profileNameInput")
                TextField("个人简介",text:$bio,axis:.vertical).lineLimit(3...5).accessibilityIdentifier("profileBioInput")
                Picker("性别",selection:$gender) {Text("不透露").tag("unspecified");Text("女").tag("female");Text("男").tag("male");Text("其他").tag("other")}
            } footer:{Text("星夜号自动生成且不可修改。昵称、头像和简介可随时调整。")}
                .listRowBackground(Theme.surface)
            if let error {Section {Text(error).foregroundStyle(Theme.peach)}.listRowBackground(Theme.surface)}
            if saving {Section {ProgressView()}.listRowBackground(Theme.surface)}
        }.font(.system(size:14)).tint(Theme.accent).scrollContentBackground(.hidden).background(Theme.background).navigationTitle("编辑资料").navigationBarTitleDisplayMode(.inline)
            .photosPicker(isPresented:$showingPhotos,selection:$selectedPhoto,matching:.images)
            .alert("需要照片访问权限",isPresented:$photoPermissionDenied) {
                Button("前往设置") {if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}
                Button("取消",role:.cancel) {}
            } message:{Text("你可以只允许选中的照片，也可以允许访问全部照片，用来选择自己的头像。")}
            .task {guard editingOwner==nil,let user=account.cloudSession?.user else{return};let p=user.profile;name=p["display_name"]?.string ?? "";bio=p["bio"]?.string ?? "在星夜，遇见温柔。";gender=p["gender"]?.string ?? "unspecified";let saved=p["avatar"]?.string ?? avatar;avatar=["starry-cat-v1","starry-bunny-v1"].contains(saved) ? "starry-orbit-v1" : saved;editingOwner=user.id;savedDraft=draft}
            .onChange(of:draft) {_,_ in scheduleSave()}
            .onSubmit {save()}
            .onDisappear {debounceTask?.cancel();save()}
            .task(id:selectedPhoto) {
                guard let item=selectedPhoto else{return}
                processing=true;defer{processing=false}
                do {
                    guard let raw=try await item.loadTransferable(type:Data.self) else{throw PlatformError.invalidResponse}
                    let result=try await Task.detached(priority:.userInitiated) {try AvatarImageProcessor.jpeg(raw)}.value
                    try Task.checkCancellation();photoData=result;error=nil
                } catch is CancellationError {} catch {self.error="这张照片暂时无法使用，请换一张。"}
            }
    }
    private func scheduleSave() {
        debounceTask?.cancel()
        guard editingOwner != nil,draft != savedDraft else {return}
        debounceTask=Task {@MainActor in
            do {try await Task.sleep(for:.milliseconds(450));try Task.checkCancellation();save()}
            catch {}
        }
    }
    private func choosePhoto() {
        Task {@MainActor in
            let current=PHPhotoLibrary.authorizationStatus(for:.readWrite)
            let status=current == .notDetermined ? await PHPhotoLibrary.requestAuthorization(for:.readWrite) : current
            if status == .authorized || status == .limited {showingPhotos=true}
            else {photoPermissionDenied=true}
        }
    }
    private func save() {
        guard !saving,!processing,draft.valid,draft != savedDraft,
              let owner=editingOwner,account.cloudSession?.user.id==owner else{return}
        saving=true;error=nil
        Task {@MainActor in
            defer {saving=false}
            do {
                // One writer owns profile versions. Edits made while an upload
                // is in flight are sent in the next iteration, never overwritten.
                while draft != savedDraft,draft.valid,!processing {
                    guard account.cloudSession?.user.id==owner else {throw CancellationError()}
                    let snapshot=draft
                    let usingUpload=account.cloudSession?.user.profile["avatar"]?.string?.hasPrefix("upload:") == true
                    if let photo=snapshot.photo,photo != uploadedPhoto || !usingUpload {
                        try await account.uploadAvatar(photo);uploadedPhoto=photo
                    }
                    guard account.cloudSession?.user.id==owner else {throw CancellationError()}
                    var fields:[String:JSONValue]=["display_name":.string(snapshot.name.trimmingCharacters(in:.whitespacesAndNewlines)),"bio":.string(snapshot.bio),"gender":.string(snapshot.gender)]
                    if snapshot.photo==nil {fields["avatar"] = .string(snapshot.avatar)}
                    try await account.saveProfile(fields);savedDraft=snapshot
                }
            }
            catch is CancellationError {} catch {self.error=error.localizedDescription;account.error=error.localizedDescription}
        }
    }
}
