import SwiftUI

struct CreateCharacterPage: View {
    @Bindable var coordinator:ViewerCoordinator
    @State private var baseID = ModelDescriptor.defaultCharacter.id
    @State private var name = "小月"
    @State private var personality = "温柔"
    @State private var tone = "自然"
    @State private var background = "住在星夜里的伙伴，喜欢听你分享日常，也有自己的小小梦想。"
    @State private var published = false
    @State private var hair = "long"
    @State private var clothing = "rose"
    @State private var height = 0.5
    @State private var creating = false
    @FocusState private var focused:Bool
    private var base:ModelDescriptor { ModelDescriptor.all.first { $0.id == baseID } ?? .defaultCharacter }
    var body:some View {
        VStack(spacing:0) {
            NightHeader(title:"创造一个，独一无二",subtitle:"给 TA 一个名字，也给故事一个开始")
            if !coordinator.account.isSignedIn {
                NightEmptyState(symbol:"sparkles",title:"让角色，有自己的归属",detail:"登录后创建，外观和故事会保存在你的本机账号下。",actionTitle:"去登录") { coordinator.requestLogin() }
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        if let author = coordinator.library.currentAuthor {
                            HStack(spacing:12) {
                                AuthorAvatar(author:author,size:38)
                                VStack(alignment:.leading,spacing:5) {
                                    Text("作者 · " + author.name).font(.system(size:13,weight:.medium))
                                    Text("角色归属于你，作者资料可在我的主页中编辑。").font(.system(size:11)).foregroundStyle(Theme.secondary)
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                        }
                        section("01  选择角色底座") {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:120))],spacing:10) {
                                ForEach(ModelDescriptor.all) { model in
                                    Button { baseID = model.id } label: {
                                        HStack(spacing:10) {
                                            Image(model.thumbnail+"Portrait").resizable().scaledToFill().frame(width:38,height:38).clipShape(Circle())
                                            Text(model.name).font(.system(size:13)).lineLimit(1)
                                            Spacer(minLength:0)
                                        }.padding(9).background(baseID == model.id ? Theme.card : Theme.surface,in:RoundedRectangle(cornerRadius:17))
                                            .overlay(RoundedRectangle(cornerRadius:17).stroke(baseID == model.id ? Theme.accent.opacity(0.8) : Theme.line,lineWidth:0.8))
                                    }.buttonStyle(.plain).accessibilityIdentifier("create-base-"+model.id)
                                }
                            }
                            Text("基于现有 3D 模型定制；模型原作者与使用范围可在关于中查看。").font(.caption2).foregroundStyle(Theme.secondary)
                        }
                        section("02  TA 是谁") {
                            TextField("角色名字",text:$name).focused($focused).accessibilityIdentifier("createName").padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:15))
                            TextField("背景与关系",text:$background,axis:.vertical).lineLimit(2...4).focused($focused).font(.subheadline)
                                .padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:15)).accessibilityIdentifier("createBackground")
                            HStack { Text("性格").font(.subheadline); Spacer(); Picker("性格",selection:$personality) { ForEach(["温柔","活泼","理性"],id:\.self) { Text($0) } } }
                            HStack { Text("语气").font(.subheadline); Spacer(); Picker("语气",selection:$tone) { ForEach(["自然","温暖","轻松"],id:\.self) { Text($0) } } }
                        }
                        if base.isLegacyHuman {
                            section("03  初见的模样") {
                                Picker("发型",selection:$hair) { Text("长发").tag("long"); Text("短发").tag("bob") }.pickerStyle(.segmented)
                                Picker("衣着",selection:$clothing) { Text("柔粉").tag("rose"); Text("浅绿").tag("sage"); Text("象牙白").tag("ivory") }.pickerStyle(.segmented)
                                HStack { Text("身高").font(.subheadline); Slider(value:$height).accessibilityLabel("创建角色身高") }
                                Text("创建后外观、性格、声音与出场画面就会固定，请在这里确认喜欢的模样。").font(.caption).foregroundStyle(Theme.secondary)
                            }
                        } else {
                            Text("角色沿用底座的声音、精致场景与取景，创建后保持固定。每位用户可以选择专属音乐、留下自己的共同记忆。").font(.caption).foregroundStyle(Theme.secondary)
                        }
                        section("属于你，或让更多人遇见") {
                            visibility(false,title:"只属于我",detail:"跟随当前本机账号，不进入其他身份的发现页",symbol:"lock")
                            visibility(true,title:"公开到发现",detail:"本机发布预览，可被另一个体验身份发现和使用",symbol:"globe.asia.australia")
                            Text("当前未接入服务器，不会上传到网络，也暂不支持跨设备同步。聊天记录和记忆始终不会随角色发布。").font(.caption).foregroundStyle(Theme.secondary).lineSpacing(3)
                        }
                        if let error = coordinator.library.error ?? coordinator.companionStore.error { Text(error).font(.caption).foregroundStyle(Theme.peach) }
                        Button(action:create) {
                            HStack { Image(systemName:"sparkles"); Text("让 TA 来到星夜"); Spacer(); Image(systemName:"arrow.right") }.frame(maxWidth:.infinity)
                        }.buttonStyle(NightPrimaryButton()).disabled(creating || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("createCharacterButton")
                    }.padding(.horizontal,24).padding(.bottom,28).frame(maxWidth:740).frame(maxWidth:.infinity)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("createPage")
    }
    private func section<Content:View>(_ title:String,@ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:13) {
            Text(title).font(.system(size:14,weight:.semibold)).foregroundStyle(Theme.accent)
            content()
        }
    }
    private func visibility(_ value:Bool,title:String,detail:String,symbol:String) -> some View {
        Button { published = value } label: {
            HStack(spacing:12) {
                Image(systemName:symbol).font(.system(size:18)).foregroundStyle(Theme.accent).frame(width:28)
                VStack(alignment:.leading,spacing:5) {
                    Text(title).font(.subheadline.weight(.medium)); Text(detail).font(.caption).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength:0)
                Image(systemName:published == value ? "checkmark.circle.fill" : "circle").foregroundStyle(published == value ? Theme.accent : Theme.secondary)
            }.padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
        }.buttonStyle(.plain).accessibilityIdentifier(value ? "createPublic" : "createPrivate").accessibilityValue(published == value ? "已选择" : "未选择")
    }
    private func create() {
        guard !creating else { return }; creating = true; focused = false
        var profile = base.collection.initialProfile(); profile.name = name
        profile.personality = personality; profile.tone = tone; profile.background = background; profile.accent = "玉青"; profile.ambience = "晚风"
        var studio = profile.resolvedStudio; studio.hair = hair; studio.clothing = clothing; studio.height = height; studio.selectEnvironment(base.collection.defaultEnvironment)
        profile.studio = studio; profile.normalize()
        if let id = coordinator.library.create(base:base,profile:profile,published:published) {
            coordinator.openCharacter(id)
        }
        creating = false
    }
}
