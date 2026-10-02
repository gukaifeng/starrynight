import SwiftUI

struct AccountProfileEditor:View {
    let account:AccountStore
    static let avatarSymbols=["moon.stars.fill","sparkles","sun.max.fill","leaf.fill","cat.fill","person.crop.circle.fill"]
    @State private var name=""
    @State private var bio=""
    @State private var gender="unspecified"
    @State private var avatar="moon.stars.fill"
    @State private var saving=false
    @State private var error:String?
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        Form {
            Section {
                HStack {Spacer();UserAccountAvatar(size:72,symbol:avatar);Spacer()}.listRowBackground(Color.clear)
                HStack {ForEach(Self.avatarSymbols,id:\.self) {symbol in
                    Button {avatar=symbol} label: {Image(systemName:symbol).frame(maxWidth:.infinity,minHeight:44)
                        .foregroundStyle(avatar==symbol ? Theme.accent : Theme.secondary)}.buttonStyle(.plain)
                }}
                TextField("昵称",text:$name).accessibilityIdentifier("profileNameInput")
                TextField("个人简介",text:$bio,axis:.vertical).lineLimit(3...5).accessibilityIdentifier("profileBioInput")
                Picker("性别",selection:$gender) {Text("不透露").tag("unspecified");Text("女").tag("female");Text("男").tag("male");Text("其他").tag("other")}
            } footer:{Text("星夜号自动生成且不可修改。昵称、头像和简介可随时调整。")}
                .listRowBackground(Theme.surface)
            if let error {Section {Text(error).foregroundStyle(Theme.peach)}.listRowBackground(Theme.surface)}
            Section {
                Button {save()} label: {HStack {Spacer();if saving {ProgressView()};Text("保存资料");Spacer()}}
                    .disabled(saving || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count>48 || bio.count>500)
                    .accessibilityIdentifier("saveAccountProfile")
            }.listRowBackground(Theme.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("编辑资料").navigationBarTitleDisplayMode(.inline)
            .task {guard let p=account.cloudSession?.user.profile else{return};name=p["display_name"]?.string ?? "";bio=p["bio"]?.string ?? "";gender=p["gender"]?.string ?? "unspecified";avatar=p["avatar"]?.string ?? avatar}
    }
    private func save() {
        saving=true;error=nil
        Task {@MainActor in
            defer {saving=false}
            do {try await account.saveProfile(["display_name":.string(name.trimmingCharacters(in:.whitespacesAndNewlines)),"bio":.string(bio),"gender":.string(gender),"avatar":.string(avatar)]);dismiss()}
            catch is CancellationError {} catch {self.error=error.localizedDescription}
        }
    }
}
