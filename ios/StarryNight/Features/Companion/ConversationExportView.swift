import SwiftUI
import UIKit
import LinkPresentation
import UniformTypeIdentifiers

struct ConversationExportView: View {
    let snapshot: ConversationExportSnapshot
    @State private var range: ConversationExportRange
    @State private var options = ConversationExportOptions()
    @State private var boundary: Boundary?
    @State private var query = ""
    @State private var result: ConversationImageResult?
    @State private var previewPage = 0
    @State private var rendering = false
    @State private var progress = "正在排版…"
    @State private var error: String?
    @State private var renderTask: Task<Void, Never>?
    @State private var sharing = false
    @Environment(\.softPanelDismiss) private var close
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Boundary { case start, end }
    private var motion: Animation { .easeInOut(duration: reduceMotion ? 0.1 : 0.25) }
    init(snapshot: ConversationExportSnapshot) {
        self.snapshot = snapshot
        _range = State(initialValue: ConversationExportRange(total: snapshot.messages.count))
    }
    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(boundary == nil ? (result == nil ? "对话长图" : "这一刻，收好了") : (boundary == .start ? "从哪句开始" : "到哪句结束"),
                            subtitle:snapshot.characterName + " · " + (result == nil ? "留住想分享的片刻" : "预览后，分享给在意的人"),
                            backID:"closeConversationExport",backAction:back)
            ZStack(alignment: .topLeading) {
                if let boundary { boundaryPicker(boundary).transition(.opacity) }
                else if let result { preview(result).transition(.opacity) }
                else { editor.transition(.opacity) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let error { Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(Theme.peach).padding(.horizontal, 22).padding(.vertical, 8).accessibilityIdentifier("conversationExportError") }
        }
        .foregroundStyle(Theme.ink).tint(Theme.accent)
        .softPanelPageSurface(opaque:true)
        .sheet(isPresented: $sharing) {
            if let result {
                ConversationImageShareSheet(pages: result.pages, characterName: snapshot.characterName, lease:result.cacheLease) { completed, shareError in
                    sharing = false
                    if !completed { Task { await CacheStorage.shared.cancelShareRetention(result.directory) } }
                    if shareError { error = "分享未完成，长图已保留，可以再次分享。" }
                }.ignoresSafeArea()
            }
        }
        .onDisappear { renderTask?.cancel() }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        if let data = snapshot.portraitPNG, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 45, height: 45).clipShape(Circle())
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("与你，留一段时光").font(.system(size: 20, weight: .regular, design: .serif))
                            Text("只有选中的文字与角色形象，会留在图里。")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }.padding(.vertical, 2)
                    if snapshot.messages.isEmpty {
                        ContentUnavailableView("还没有可以珍藏的对话", systemImage: "text.bubble", description: Text("和角色聊几句，再来收好这段时光。"))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("选择片段").font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text("已选 \(range.count) 条").font(.system(size: 12)).foregroundStyle(Theme.peach)
                                    .accessibilityIdentifier("exportSelectionCount")
                            }
                            HStack(spacing: 8) {
                                preset("最近 10 条", count: 10, id: "recent10")
                                preset("最近 30 条", count: 30, id: "recent30")
                                preset("全部", count: snapshot.messages.count, id: "all")
                            }
                            VStack(spacing: 0) {
                                endpoint(.start, index: range.lower)
                                Rectangle().fill(Theme.line.opacity(0.45)).frame(height: 0.5).padding(.horizontal, 14)
                                endpoint(.end, index: range.upper)
                            }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("纸上的氛围").font(.system(size: 13, weight: .medium))
                            HStack(spacing: 12) {
                                ForEach(ConversationImageStyle.allCases) { style in
                                    styleCard(style)
                                }
                            }
                            Toggle("显示消息日期与时间", isOn: $options.showsDates)
                                .font(.system(size: 13)).padding(.top, 2).disabled(rendering).accessibilityIdentifier("exportDatesToggle")
                        }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 18)
            }.scrollIndicators(.hidden).accessibilityIdentifier("exportEditorScroll")
            VStack(spacing: 8) {
                if rendering {
                    HStack(spacing: 10) { ProgressView().tint(Theme.accent); Text(LocalizedStringKey(progress)).font(.system(size: 13)) }
                        .padding(.vertical, 14).accessibilityIdentifier("exportRenderingProgress")
                    Button("取消生成") { renderTask?.cancel() }.font(.system(size: 12)).accessibilityIdentifier("cancelExportRendering")
                } else {
                    Button(action: generate) {
                        Label("生成长图", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }.buttonStyle(NightPrimaryButton()).disabled(range.count == 0).accessibilityIdentifier("generateConversationImage")
                    Text("高清原图 · 过长时自动分图，内容不会省略")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 18)
        }
    }
    private func preset(_ label: String, count: Int, id: String) -> some View {
        Button(label) { range = ConversationExportRange(total: snapshot.messages.count, recent: count) }
            .font(.system(size: 12, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 9)
            .background(Theme.surface, in: Capsule()).buttonStyle(.plain).disabled(rendering)
            .accessibilityIdentifier("exportRange-" + id)
    }
    private func endpoint(_ edge: Boundary, index: Int) -> some View {
        Button {
            query = ""; withAnimation(motion) { boundary = edge }
        } label: {
            HStack(spacing: 12) {
                Text(edge == .start ? "起" : "止").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.peach)
                    .frame(width: 26, height: 26).background(Theme.peach.opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    let message = snapshot.messages[index]
                    Text("第 \(index + 1) 条 · " + (message.role == "user" ? "我" : snapshot.characterName))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text(message.text).font(.system(size: 13)).lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(rendering).accessibilityIdentifier(edge == .start ? "exportStart" : "exportEnd")
    }
    private func styleCard(_ style: ConversationImageStyle) -> some View {
        Button { options.style = style } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: style == .moon ? "moon.stars" : "sun.horizon").font(.system(size: 19, weight: .light))
                    Spacer()
                    if options.style == style { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)) }
                }
                Text(LocalizedStringKey(style.name)).font(.system(size: 14, weight: .semibold))
                Text(LocalizedStringKey(style.detail)).font(.system(size: 10)).opacity(0.7)
            }.foregroundStyle(style == .moon ? Color(hex: 0xF3ECE1) : Color(hex: 0x574638))
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(style == .moon ? Color(hex: 0x222B36) : Color(hex: 0xEFE4D2), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(options.style == style ? Theme.peach : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(rendering).accessibilityIdentifier("exportStyle-" + style.rawValue)
            .accessibilityValue(options.style == style ? "已选" : "未选")
    }
    private func boundaryPicker(_ edge: Boundary) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("搜索这段聊天", text: $query).font(.system(size: 13)).accessibilityIdentifier("exportRangeSearch")
            }.padding(12).background(Theme.surface, in: Capsule()).padding(.horizontal, 22)
            Text("选择后会保留起止之间的所有消息").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(snapshot.messages.enumerated()), id: \.element.id) { index, message in
                            if query.isEmpty || message.text.localizedCaseInsensitiveContains(query) {
                                Button {
                                    if edge == .start { range.setStart(index) } else { range.setEnd(index) }
                                    withAnimation(motion) { boundary = nil }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: (edge == .start ? range.lower : range.upper) == index ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(Theme.peach).font(.system(size: 17)).padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("\(index + 1) · " + (message.role == "user" ? "我" : snapshot.characterName))
                                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                            Text(message.text).font(.system(size: 13)).lineLimit(3).multilineTextAlignment(.leading)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 15)).contentShape(Rectangle())
                                }.buttonStyle(.plain).id(index).accessibilityIdentifier("exportMessage-\(index)")
                            }
                        }
                    }.padding(.horizontal, 22).padding(.bottom, 20)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("exportBoundaryScroll")
                    .onAppear { reader.scrollTo(edge == .start ? range.lower : range.upper, anchor: .center) }
            }
        }
    }
    private func preview(_ result: ConversationImageResult) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(result.messageCount) 条 · \(result.pages.count) 张长图").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("exportPreviewSummary")
                Spacer()
                Text("1080 px").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.peach)
            }.padding(.horizontal, 22)
            ScrollViewReader { reader in
                ScrollView {
                    if let image = UIImage(contentsOfFile: result.pages[previewPage].previewURL.path) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 22).padding(.bottom, 12).id("imageTop")
                            .accessibilityLabel("与" + snapshot.characterName + "的对话长图预览")
                            .accessibilityIdentifier("conversationImagePreview")
                    }
                }.scrollIndicators(.hidden).onChange(of: previewPage) { _, _ in reader.scrollTo("imageTop", anchor: .top) }
            }
            if result.pages.count > 1 {
                HStack(spacing: 28) {
                    Button { previewPage -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 32) }.disabled(previewPage == 0)
                    Text("\(previewPage + 1) / \(result.pages.count)").font(.system(size: 12, design: .monospaced))
                    Button { previewPage += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 32) }.disabled(previewPage == result.pages.count - 1)
                }.buttonStyle(.plain)
            }
            Button {
                error = nil
                Task {
                    do { try await CacheStorage.shared.retainSharedExport(result.directory); sharing = true }
                    catch { self.error = "长图暂时无法读取，请重新生成后分享。" }
                }
            } label: {
                Label(result.pages.count == 1 ? "分享这段时光" : "分享全部 \(result.pages.count) 张", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(NightPrimaryButton()).accessibilityIdentifier("shareConversationImage")
                .padding(.horizontal, 22).padding(.bottom, 18)
        }
    }
    private func generate() {
        guard !rendering else { return }
        error = nil; rendering = true; progress = "正在排版…"
        let frozenOptions = options, frozenRange = range
        renderTask = Task {
            do {
                let images = try await ConversationImageExporter.shared.export(snapshot: snapshot, range: frozenRange, options: frozenOptions) { done, total in
                    await MainActor.run { progress = "正在生成 \(min(done + 1, total)) / \(total)…" }
                }
                try Task.checkCancellation()
                previewPage = 0
                withAnimation(motion) { result = images }
            } catch is CancellationError { /* Back/cancel is intentional, not a failure. */ }
            catch { self.error = (error as? ConversationExportError)?.errorDescription ?? "长图未能保存，请检查可用空间后重试。" }
            rendering = false; renderTask = nil
        }
    }
    private func back() {
        if boundary != nil { withAnimation(motion) { boundary = nil } }
        else if result != nil { withAnimation(motion) { result = nil; error = nil } }
        else { renderTask?.cancel(); close() }
    }
}

/// Send PNG file URLs, not a screenshot, text dump or private archive. The system
/// decides which installed apps can receive images; the user picks the recipient.
private struct ConversationImageShareSheet: UIViewControllerRepresentable {
    let pages: [ConversationImagePage]
    let characterName: String
    let lease: CacheFileLease?
    var completion: (Bool,Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let sources = pages.map { ConversationImageShareItem(page: $0, title: "与\(characterName)的对话 · 星夜",lease:lease) }
        let controller = UIActivityViewController(activityItems: sources, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in completion(completed,error != nil) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
private final class ConversationImageShareItem: NSObject, UIActivityItemSource {
    let page: ConversationImagePage
    let title: String
    let lease: CacheFileLease?
    init(page: ConversationImagePage, title: String, lease: CacheFileLease?) { self.page = page; self.title = title; self.lease = lease }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { page.imageURL }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { page.imageURL }
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String { UTType.png.identifier }
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata(); metadata.title = title
        metadata.imageProvider = NSItemProvider(contentsOf: page.previewURL)
        return metadata
    }
}
