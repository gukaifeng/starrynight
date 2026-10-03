import SwiftUI
import Observation

enum CacheSize {
    static func text(_ bytes: Int64) -> String {
        bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)
    }
}

@MainActor @Observable
final class CacheSettingsModel {
    var snapshot: CacheSnapshot?
    var selected = Set(CacheCategory.allCases)
    var busy = false
    var clearing = false
    var message: String?
    private let coordinator: ViewerCoordinator
    private let storage: CacheStorage
    init(coordinator: ViewerCoordinator, storage: CacheStorage = .shared) {
        self.coordinator = coordinator; self.storage = storage
    }
    var canClear: Bool { !busy && (snapshot?.removableFiles(in:selected) ?? 0) > 0 }
    var selectedBytes: Int64 { snapshot?.removableBytes(in:selected) ?? 0 }
    func refresh() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        snapshot = await storage.snapshot()
    }
    func clear() async {
        guard canClear else { return }
        let categories = selected
        busy = true; clearing = true; message = nil
        var production = true
#if DEBUG && targetEnvironment(simulator)
        production = !ProcessInfo.processInfo.arguments.contains("--cache-fixture")
#endif
        if production { coordinator.beginCacheClear(categories) }
        defer {
            if production { coordinator.endCacheClear(categories) }
            busy = false; clearing = false
        }
        let result = await storage.clear(categories)
        snapshot = result.snapshot
        if result.failures > 0 {
            message = "已清理 \(CacheSize.text(result.removedBytes))，部分文件暂时无法处理，请稍后重试。"
        } else if result.removedFiles == 0 {
            message = result.snapshot.protectedBytes > 0 ? "正在使用或最近分享的文件暂时保留。" : "暂时没有可清理的缓存。"
        } else { message = "已清理 \(CacheSize.text(result.removedBytes))，聊天和角色资料已保留。" }
    }
}

struct CacheSettingsView: View {
    let coordinator:ViewerCoordinator
    @State private var model: CacheSettingsModel
    @Environment(\.scenePhase) private var scenePhase
    init(coordinator: ViewerCoordinator) {self.coordinator=coordinator; _model = State(initialValue:CacheSettingsModel(coordinator:coordinator)) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("应用缓存").font(.system(size:13)).foregroundStyle(Theme.secondary)
                        Text(model.snapshot.map { CacheSize.text($0.bytes) } ?? "正在计算…")
                            .font(.system(size:32,weight:.medium,design:.rounded)).monospacedDigit()
                            .contentTransition(.numericText()).accessibilityIdentifier("cacheTotalSize")
                    }
                    Spacer()
                    Button { Task { await model.refresh() } } label: {
                        Group {
                            if model.busy { ProgressView().tint(Theme.accent) }
                            else { Image(systemName:"arrow.clockwise").font(.system(size:16,weight:.medium)) }
                        }.frame(width:44,height:44).background(Theme.surface,in:Circle())
                    }.buttonStyle(.plain).disabled(model.busy).accessibilityLabel("重新计算缓存").accessibilityIdentifier("refreshCacheButton")
                }.padding(.top,4)
                Text("声音、头像和长图可以重新准备。清理不会删除聊天、账号、订阅或角色定制。")
                    .font(.system(size:13)).lineSpacing(4).foregroundStyle(Theme.secondary)
                NavigationLink {CharacterResourceSettingsView(coordinator:coordinator)} label: {
                    HStack(spacing:12) {
                        Image(systemName:"square.stack.3d.up").font(.system(size:19,weight:.light)).foregroundStyle(Theme.peach).frame(width:30)
                        VStack(alignment:.leading,spacing:5) {
                            Text("角色资源").font(.system(size:14,weight:.medium))
                            Text("查看下载占用 · 按角色删除本地资源").font(.system(size:11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer();Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(Theme.secondary)
                    }.padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))
                }.buttonStyle(.plain).accessibilityIdentifier("characterResourceSettingsButton")
                VStack(spacing:0) {
                    ForEach(model.snapshot?.categories ?? CacheCategory.allCases.map { CacheUsage(category:$0) }) { usage in
                        row(usage)
                        if usage.category != .exports { Rectangle().fill(Theme.line.opacity(0.45)).frame(height:0.5).padding(.leading,58) }
                    }
                }.padding(.horizontal,16).background(Theme.surface,in:RoundedRectangle(cornerRadius:20))
                if let snapshot = model.snapshot, snapshot.protectedBytes > 0 {
                    Label {
                        Text("暂时保留 \(CacheSize.text(snapshot.protectedBytes))\n正在使用的长图暂不清理。最近分享的副本在分享 24 小时后可清理。")
                            .font(.system(size:12)).lineSpacing(4)
                    } icon: { Image(systemName:"clock").font(.system(size:13)) }
                    .foregroundStyle(Theme.secondary).accessibilityIdentifier("cacheProtectedNote")
                }
                if let snapshot = model.snapshot, snapshot.issues > 0 {
                    Text("部分文件暂时无法读取，当前显示可读取的缓存。可以点右上角重新计算。")
                        .font(.footnote).foregroundStyle(Theme.peach).accessibilityIdentifier("cacheScanError")
                }
                VStack(spacing:12) {
                    Button { Task { await model.clear() } } label: {
                        HStack(spacing:8) {
                            if model.clearing { ProgressView().tint(Theme.background) }
                            Text(model.clearing ? "正在清理…" : "清理所选缓存")
                            if !model.clearing && model.selectedBytes > 0 { Text(CacheSize.text(model.selectedBytes)).font(.system(size:13)).monospacedDigit() }
                        }.frame(maxWidth:.infinity)
                    }.buttonStyle(NightPrimaryButton()).disabled(!model.canClear)
                        .opacity(model.canClear || model.clearing ? 1 : 0.45).accessibilityIdentifier("clearCacheButton")
                    if let message = model.message {
                        Text(LocalizedStringKey(message)).font(.system(size:12)).lineSpacing(4).foregroundStyle(Theme.peach)
                            .frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("cacheClearResult")
                    } else if let snapshot = model.snapshot, snapshot.categories.allSatisfy({ $0.files == 0 }) {
                        Text("暂时没有缓存需要清理。正常使用后，会在这里更新。")
                            .font(.system(size:12)).foregroundStyle(Theme.secondary).frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                Text("缓存按本机统计。内置 3D 模型和已保存的资料不计入可清理缓存。")
                    .font(.system(size:11)).lineSpacing(4).foregroundStyle(Theme.secondary.opacity(0.85))
            }.padding(24)
        }.scrollIndicators(.hidden).background(Theme.background)
            .foregroundStyle(Theme.ink).tint(Theme.accent)
            .navigationTitle("存储与缓存").navigationBarTitleDisplayMode(.inline)
            .task { await model.refresh() }
            .onChange(of:scenePhase) { _, value in if value == .active { Task { await model.refresh() } } }
    }
    private func row(_ usage: CacheUsage) -> some View {
        let selected = model.selected.contains(usage.category)
        return Button {
            if selected { model.selected.remove(usage.category) } else { model.selected.insert(usage.category) }
        } label: {
            HStack(spacing:12) {
                Image(systemName:usage.category.symbol).font(.system(size:19,weight:.light)).foregroundStyle(Theme.peach).frame(width:30)
                VStack(alignment:.leading,spacing:6) {
                    HStack {
                        Text(LocalizedStringKey(usage.category.title)).font(.system(size:14,weight:.medium))
                        Spacer(minLength:4)
                        Text(model.snapshot == nil ? "—" : CacheSize.text(usage.bytes)).font(.system(size:12)).monospacedDigit().foregroundStyle(Theme.secondary)
                    }
                    Text(LocalizedStringKey(usage.category.detail)).font(.system(size:11)).lineSpacing(3).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                }
                Image(systemName:selected ? "checkmark.circle.fill" : "circle").font(.system(size:18)).foregroundStyle(selected ? Theme.accent : Theme.secondary)
            }.padding(.vertical,18).frame(maxWidth:.infinity,minHeight:72).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(model.busy).accessibilityIdentifier("cacheCategory-"+usage.category.rawValue)
            .accessibilityLabel(usage.category.title + "，" + CacheSize.text(usage.bytes))
            .accessibilityValue(selected ? "已选择" : "未选择")
    }
}
