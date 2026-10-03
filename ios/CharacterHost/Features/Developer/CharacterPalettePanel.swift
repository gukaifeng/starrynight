#if STARRY_TEST_TOOLS
import SwiftUI
import Observation

struct CharacterPaletteTone:Codable,Equatable {
    var hue:Double=0
    var saturation:Double=1
    var exposure:Double=0
    var tint:Double=0
    var payload:[String:Any] {["hue":hue,"saturation":saturation,"exposure":exposure,"tint":tint]}
    var neutral:Bool {self == Self()}
}
struct CharacterPaletteRGBA:Decodable {var r,g,b,a:Double;var color:Color {Color(red:max(0,min(1,r)),green:max(0,min(1,g)),blue:max(0,min(1,b)))}}
struct CharacterPaletteChannel:Decodable,Identifiable {var id,label:String;var color:CharacterPaletteRGBA;var hdr:Bool}
struct CharacterPaletteComponent:Decodable,Identifiable {
    var id,name,path,material,shader:String
    var visible,supported:Bool
    var slot:Int
    var channels:[CharacterPaletteChannel]
    var displayName:String {
        let raw=(name+" "+material).lowercased()
        let terms:[(String,[String])]=[("头发",["hair","髪"]),("眼睛",["eye","iris","目"]),("面部",["face","顔"]),("皮肤",["skin","肌"]),("衣服",["cloth","dress","shirt","服"]),("身体",["body","体"]),("耳朵",["ear","耳"]),("尾巴",["tail","尻尾"]),("配饰",["accessory","ribbon","アクセ"])]
        if let term=terms.first(where:{$0.1.contains(where:{raw.contains($0)})}) {return term.0+" · "+name}
        return name
    }
}
private struct CharacterPaletteCatalog:Decodable {var revision:Int;var modelId:String;var components:[CharacterPaletteComponent]}

/// Developer preferences remain local and scoped to account + role. The native
/// host owns persistence; a downloaded package's immutable source stays intact.
@MainActor @Observable final class CharacterPaletteState {
    private(set) var modelID=""
    private(set) var presentation = -1
    private(set) var components:[CharacterPaletteComponent]=[]
    private(set) var ready=false
    private(set) var failure:String?
    private(set) var engineEditedSlots=0
    private(set) var styles:[String:[String:CharacterPaletteTone]]=[:]
    @ObservationIgnored var send:(String,[String:Any])->Void = {_,_ in}
    @ObservationIgnored private var storageKey=""
    @ObservationIgnored private var pending:Task<Void,Never>?
    @ObservationIgnored private var queryTask:Task<Void,Never>?
    @ObservationIgnored private var pendingEdits:[String:(String,String,CharacterPaletteTone)]=[:]
    @ObservationIgnored private var pendingRestore=false
    var suggestedComponentID:String {
        let visible=components.filter {$0.visible && $0.supported && !($0.material.lowercased().contains("effect") || $0.material.lowercased().contains("shadow"))}
        return visible.first(where:{($0.name+" "+$0.material).lowercased().contains("hair") || ($0.name+" "+$0.material).contains("髪")})?.id ?? visible.first?.id ?? components.first?.id ?? ""
    }
    func begin(account:String,modelID:String,presentation:Int) {
        pending?.cancel();queryTask?.cancel()
        pendingEdits=[:];pendingRestore=false
        self.modelID=modelID;self.presentation=presentation;components=[];ready=false;failure=nil;engineEditedSlots=0
        storageKey="StarryNight.developerPalette.v1."+account+"."+modelID
        styles=UserDefaults.standard.data(forKey:storageKey).flatMap {try? JSONDecoder().decode([String:[String:CharacterPaletteTone]].self,from:$0)} ?? [:]
    }
    func request() {
        failure=nil;send("getPalette",["modelId":modelID]);queryTask?.cancel()
        queryTask=Task {try? await Task.sleep(for:.seconds(6));if !Task.isCancelled && !ready {failure="颜色目录尚未就绪，请刷新重试。"}}
    }
    func receive(_ event:[String:Any]) {
        guard event["modelId"] as? String==modelID,event["presentationId"] as? Int==presentation else {return}
        if ["palette","paletteApplied"].contains(event["name"] as? String ?? ""),let value=event["palette"] as? [String:Any] {engineEditedSlots=value["editedSlots"] as? Int ?? engineEditedSlots}
        guard event["name"] as? String == "palette",
              let raw=event["palette"],let data=try? JSONSerialization.data(withJSONObject:raw),let catalog=try? JSONDecoder().decode(CharacterPaletteCatalog.self,from:data),catalog.revision==1,catalog.modelId==modelID else {return}
        components=catalog.components;ready=true;failure=nil;queryTask?.cancel()
        if pendingRestore {
            pendingRestore=false
            for item in components where item.supported {
                let valid=Set(["$main","$shadow","$highlight"]+item.channels.map(\.id))
                for (channel,tone) in styles[item.id] ?? [:] where valid.contains(channel) {apply(item.id,channel,tone)}
            }
        }
    }
    func restore() {
        // Validate the fresh package's component IDs before replaying preferences;
        // a future asset release can remove a garment or rename a source channel.
        pendingRestore = !styles.isEmpty
        var payload:[String:Any]=["modelId":modelID,"immediate":true]
        if pendingRestore {payload["palette"]=["component":""]}
        send("resetPalette",payload)
    }
    func tone(_ component:String,_ channel:String)->CharacterPaletteTone {styles[component]?[channel] ?? .init()}
    private func apply(_ component:String,_ channel:String,_ tone:CharacterPaletteTone) {
        send("setPalette",["modelId":modelID,"palette":["component":component,"channel":channel,"tone":tone.payload]])
    }
    func edit(_ component:String,_ channel:String,_ tone:CharacterPaletteTone) {
        guard components.contains(where:{$0.id==component && $0.supported}) else {return}
        styles[component,default:[:]][channel]=tone
        if tone.neutral {styles[component]?.removeValue(forKey:channel)}
        if styles[component]?.isEmpty == true {styles.removeValue(forKey:component)}
        persist()
        pendingEdits[component+"\n"+channel]=(component,channel,tone)
        // Coalesce slider events, but flush the last position when leaving.
        pending?.cancel()
        pending=Task {try? await Task.sleep(for:.milliseconds(50));guard !Task.isCancelled else {return};flush()}
    }
    func flush() {
        pending?.cancel()
        let edits=Array(pendingEdits.values);pendingEdits=[:]
        for (component,channel,tone) in edits {apply(component,channel,tone)}
    }
    func reset(_ component:String?=nil) {
        pending?.cancel()
        pendingEdits=[:]
        pendingRestore=false
        if let component {styles.removeValue(forKey:component)} else {styles=[:]}
        persist();send("resetPalette",["modelId":modelID,"palette":["component":component ?? ""]])
    }
    private func persist() {if let data=try? JSONEncoder().encode(styles) {UserDefaults.standard.set(data,forKey:storageKey)}}
}

struct CharacterPalettePanel:View {
    let model:ModelDescriptor
    let state:CharacterPaletteState?
    var onOpenPreview:()->Void = {}
    @State private var selected=""
    @State private var channel="$main"
    @State private var query=""
    @State private var visibleOnly=false
    @State private var showsComponents=true
    @State private var resetAll=false
    private var component:CharacterPaletteComponent? {state?.components.first(where:{$0.id==selected})}
    private var tone:CharacterPaletteTone {state?.tone(selected,channel) ?? .init()}
    private var filtered:[CharacterPaletteComponent] {(state?.components ?? []).filter {(!visibleOnly || $0.visible) && (query.isEmpty || ($0.displayName+" "+$0.material+" "+$0.path).localizedCaseInsensitiveContains(query))}}
    private func binding(_ path:WritableKeyPath<CharacterPaletteTone,Double>)->Binding<Double> {
        Binding(get:{tone[keyPath:path]},set:{value in var next=tone;next[keyPath:path]=value;state?.edit(selected,channel,next)})
    }
    var body:some View {
        VStack(spacing:0) {
            PanelPageHeader("定制颜色 · "+model.name,backID:"closeCharacterPalette") {
                Button {resetAll=true} label:{Image(systemName:"arrow.counterclockwise").font(.system(size:13)).frame(width:36,height:40)}
                    .accessibilityLabel("恢复全部原作颜色").accessibilityIdentifier("paletteResetAll")
            }
            if let state {
                Text(state.ready ? "颜色实验 · \(state.components.count) 个材质槽" : "正在读取颜色目录")
                    .font(.system(size:10)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,20).padding(.bottom,7)
                    .accessibilityIdentifier("paletteStatus")
                    .accessibilityValue("model:\(state.modelID);ready:\(state.ready);components:\(state.components.count);engineEdits:\(state.engineEditedSlots)")
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        if !state.ready {
                            HStack {ProgressView();Text(state.failure ?? "正在读取模型的全部材质…").font(.system(size:12))}
                            Button("刷新颜色目录") {state.request()}.font(.system(size:12))
                        } else {
                            componentBrowser
                            if let component {
                                colorStudio(component)
                            }
                            Text("保留原作的纹理与光影 · 自动保存到当前账号与角色\n共享贴图里的部位会一起变化；这里不会改动角色原文件。")
                                .font(.system(size:10)).foregroundStyle(Theme.secondary).lineSpacing(3)
                        }
                    }.padding(.horizontal,20).padding(.bottom,24)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            } else {
                VStack(spacing:16) {
                    Image(systemName:"paintpalette").font(.system(size:30)).foregroundStyle(Theme.accent)
                    Text("在角色身边，试一组新颜色").font(.system(size:16,weight:.medium))
                    Text("先载入这个角色，才能读取全部组件并实时预览。").font(.system(size:12)).foregroundStyle(Theme.secondary)
                    Button("载入角色后调色",action:onOpenPreview).buttonStyle(.borderedProminent)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.foregroundStyle(Theme.ink).tint(Theme.accent).softPanelPageSurface()
            .task {state?.request()}
            .onChange(of:state?.ready) {_,ready in
                if ready == true,component==nil {selected=state?.suggestedComponentID ?? ""}
            }
            .onAppear {if component==nil {selected=state?.suggestedComponentID ?? ""}}
            .onDisappear {state?.flush()}
            .confirmationDialog("恢复这个角色全部原作颜色？",isPresented:$resetAll,titleVisibility:.visible) {
                Button("恢复原作",role:.destructive) {state?.reset()}
            }.accessibilityElement(children:.contain).accessibilityIdentifier("characterPalettePanel")
    }
    private var componentBrowser:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Button {withAnimation(.easeInOut(duration:0.2)) {showsComponents.toggle()}} label:{
                    HStack(spacing:7) {Image(systemName:"square.stack.3d.up");Text("组件与材质 · \(state?.components.count ?? 0)");Image(systemName:showsComponents ? "chevron.up" : "chevron.down").font(.system(size:9))}
                }.font(.system(size:12,weight:.medium)).buttonStyle(.plain)
                Spacer()
                HStack(spacing:3) {
                    Text("仅显示中").font(.system(size:10)).foregroundStyle(Theme.secondary)
                    Toggle("显示中",isOn:$visibleOnly).labelsHidden().scaleEffect(0.7,anchor:.trailing).frame(width:40)
                        .accessibilityLabel("只看显示中的组件")
                }
            }
            if showsComponents {
                HStack(spacing:7) {Image(systemName:"magnifyingglass");TextField("搜索头发、衣服、皮肤或原作名称",text:$query)}
                    .font(.system(size:11)).foregroundStyle(Theme.secondary).padding(9).background(Theme.surface.opacity(0.7),in:RoundedRectangle(cornerRadius:10))
                ScrollView {
                    LazyVStack(spacing:2) {
                        ForEach(filtered) {item in
                            Button {selected=item.id;channel="$main"} label:{
                                HStack(spacing:7) {
                                    Circle().fill(item.channels.first?.color.color ?? Theme.accent).frame(width:8,height:8)
                                    VStack(alignment:.leading,spacing:2) {
                                        Text(item.displayName+" · "+item.material).font(.system(size:11,weight:.medium)).lineLimit(1)
                                        Text("槽 \(item.slot+1) · \(item.channels.count) 个原作颜色通道"+(item.visible ? "" : " · 隐藏组件"))
                                            .font(.system(size:9)).foregroundStyle(Theme.secondary)
                                    }
                                    Spacer(minLength:0)
                                    Image(systemName:selected==item.id ? "checkmark.circle.fill" : item.supported ? "circle" : "exclamationmark.circle").font(.system(size:12))
                                }.padding(.vertical,7).padding(.horizontal,8).background(selected==item.id ? Theme.accent.opacity(0.1) : .clear,in:RoundedRectangle(cornerRadius:9))
                            }.buttonStyle(.plain).accessibilityIdentifier("paletteComponent-"+item.id)
                        }
                    }
                }.frame(height:125).scrollIndicators(.hidden).accessibilityIdentifier("paletteComponents")
            }
        }
    }
    private func colorStudio(_ component:CharacterPaletteComponent)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:3) {
                    Text(component.material).font(.system(size:14,weight:.medium)).lineLimit(1)
                    Text(component.path).font(.system(size:9)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer()
                Button {state?.reset(selected)} label:{Image(systemName:"arrow.counterclockwise").font(.system(size:12)).frame(width:32,height:30)}
                    .accessibilityLabel("恢复当前组件").accessibilityIdentifier("paletteResetComponent")
            }
            RoundedRectangle(cornerRadius:8).fill(LinearGradient(colors:previewColors, startPoint:.leading,endPoint:.trailing)).frame(height:28)
                .overlay(alignment:.bottom) {HStack {Text("暗部");Spacer();Text("主色");Spacer();Text("亮部")}.font(.system(size:8,weight:.medium)).foregroundStyle(.white.opacity(0.65)).padding(.horizontal,9).padding(.bottom,4)}
            Picker("色系层次",selection:Binding(get:{channel.hasPrefix("$") ? channel : "$source"},set:{channel=$0 == "$source" ? (component.channels.first(where:{$0.id=="_Color"})?.id ?? component.channels.first?.id ?? "$main") : $0})) {
                Text("整体").tag("$main");Text("暗部").tag("$shadow");Text("亮部").tag("$highlight");Text("原作").tag("$source")
            }
                .pickerStyle(.segmented).accessibilityIdentifier("paletteBands")
            Menu {
                ForEach(component.channels) {item in Button(item.label+" · "+item.id+(item.hdr ? " · HDR" : "")) {channel=item.id}}
            } label:{
                HStack {Image(systemName:"slider.horizontal.3");Text(channel.hasPrefix("$") ? "原作颜色通道 · \(component.channels.count)" : component.channels.first(where:{$0.id==channel})?.label ?? channel);Spacer();Image(systemName:"chevron.down")}
                    .font(.system(size:11)).foregroundStyle(Theme.secondary)
            }.accessibilityIdentifier("paletteSourceChannels")
            if !component.supported {Text("这个材质暂未提供兼容调色器。原作效果保持不变。").font(.system(size:12))}
            VStack(spacing:10) {
                precision("色相",value:binding(\.hue),range:-180...180,step:0.1,display:String(format:"%+.1f°",tone.hue),id:"paletteHue")
                precision("鲜度",value:binding(\.saturation),range:0...2,step:0.01,display:String(format:"%.0f%%",tone.saturation*100),id:"paletteSaturation")
                precision("明度",value:binding(\.exposure),range:-2...2,step:0.01,display:String(format:"%+.2f EV",tone.exposure),id:"paletteExposure")
                precision("染色",value:binding(\.tint),range:0...1,step:0.01,display:String(format:"%.0f%%",tone.tint*100),id:"paletteTint")
            }.disabled(!component.supported)
            Text("染色让白色与灰色也染上新色；暗部和亮部独立微调，保留纹理的明暗关系。")
                .font(.system(size:10)).foregroundStyle(Theme.secondary)
        }
    }
    private var previewColors:[Color] {
        let hue=(tone.hue/360+0.58).truncatingRemainder(dividingBy:1)
        return [Color(hue:hue<0 ? hue+1:hue,saturation:min(1,tone.saturation*0.4+tone.tint*0.4),brightness:0.22),
                Color(hue:hue<0 ? hue+1:hue,saturation:min(1,tone.saturation*0.5+tone.tint*0.4),brightness:0.62),
                Color(hue:hue<0 ? hue+1:hue,saturation:min(1,tone.saturation*0.3+tone.tint*0.4),brightness:0.94)]
    }
    private func precision(_ title:String,value:Binding<Double>,range:ClosedRange<Double>,step:Double,display:String,id:String)->some View {
        VStack(spacing:3) {
            HStack {Text(title).font(.system(size:11,weight:.medium));Spacer();Text(display).font(.system(size:10,design:.monospaced)).foregroundStyle(Theme.secondary)}
            HStack(spacing:9) {
                Button {value.wrappedValue=max(range.lowerBound,value.wrappedValue-step)} label:{Image(systemName:"minus").frame(width:26,height:26)}.accessibilityLabel(title+"减小")
                Slider(value:value,in:range).accessibilityLabel(title).accessibilityIdentifier(id)
                Button {value.wrappedValue=min(range.upperBound,value.wrappedValue+step)} label:{Image(systemName:"plus").frame(width:26,height:26)}.accessibilityLabel(title+"增加")
            }.font(.system(size:10)).buttonStyle(.plain)
        }
    }
}
#endif
