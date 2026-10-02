import SwiftUI
import PhotosUI

struct AccountProfileEditor:View {
    let account:AccountStore
    static let avatarSymbols=["moon.stars.fill","sparkles","sun.max.fill","leaf.fill","cat.fill","person.crop.circle.fill"]
    static let starryAvatars=["starry-cat-v1","starry-bunny-v1","starry-orbit-v1"]
    @State private var name=""
    @State private var bio=""
    @State private var gender="unspecified"
    @State private var avatar="starry-cat-v1"
    @State private var selectedPhoto:PhotosPickerItem?
    @State private var photoData:Data?
    @State private var processing=false
    @State private var saving=false
    @State private var error:String?
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        Form {
            Section {
                HStack {Spacer();UserAccountAvatar(size:72,symbol:avatar,preview:photoData.flatMap {UIImage(data:$0)});Spacer()}.listRowBackground(Color.clear)
                HStack(spacing:20) {ForEach(Self.starryAvatars,id:\.self) {choice in
                    Button {avatar=choice;photoData=nil;selectedPhoto=nil} label: {
                        StarryDefaultAvatar(kind:choice).frame(width:44,height:44).clipShape(Circle())
                            .overlay(Circle().stroke(Theme.accent.opacity(avatar==choice ? 0.9 : 0.08),lineWidth:2))
                    }.buttonStyle(.plain).accessibilityLabel(choice=="starry-cat-v1" ? "小夜猫" : choice=="starry-bunny-v1" ? "月亮兔" : "小星球")
                        .accessibilityIdentifier("avatar-"+choice)
                };Spacer(minLength:0)
                    PhotosPicker(selection:$selectedPhoto,matching:.images) {Image(systemName:"photo.badge.plus").font(.system(size:20,weight:.light)).frame(width:44,height:44)}
                        .accessibilityLabel("从相册选择头像").accessibilityIdentifier("chooseAccountPhoto")
                }
                if processing {ProgressView("正在准备头像…")}
                TextField("昵称",text:$name).accessibilityIdentifier("profileNameInput")
                TextField("个人简介",text:$bio,axis:.vertical).lineLimit(3...5).accessibilityIdentifier("profileBioInput")
                Picker("性别",selection:$gender) {Text("不透露").tag("unspecified");Text("女").tag("female");Text("男").tag("male");Text("其他").tag("other")}
            } footer:{Text("星夜号自动生成且不可修改。昵称、头像和简介可随时调整。")}
                .listRowBackground(Theme.surface)
            if let error {Section {Text(error).foregroundStyle(Theme.peach)}.listRowBackground(Theme.surface)}
            Section {
                Button {save()} label: {HStack {Spacer();if saving {ProgressView()};Text("保存资料");Spacer()}}
                    .disabled(saving || processing || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count>48 || bio.count>500)
                    .accessibilityIdentifier("saveAccountProfile")
            }.listRowBackground(Theme.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("编辑资料").navigationBarTitleDisplayMode(.inline)
            .task {guard let p=account.cloudSession?.user.profile else{return};name=p["display_name"]?.string ?? "";bio=p["bio"]?.string ?? "";gender=p["gender"]?.string ?? "unspecified";avatar=p["avatar"]?.string ?? avatar}
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
    private func save() {
        saving=true;error=nil
        Task {@MainActor in
            defer {saving=false}
            do {
                if let photoData {try await account.uploadAvatar(photoData)}
                var fields:[String:JSONValue]=["display_name":.string(name.trimmingCharacters(in:.whitespacesAndNewlines)),"bio":.string(bio),"gender":.string(gender)]
                if photoData==nil {fields["avatar"] = .string(avatar)}
                try await account.saveProfile(fields);dismiss()
            }
            catch is CancellationError {} catch {self.error=error.localizedDescription}
        }
    }
}
