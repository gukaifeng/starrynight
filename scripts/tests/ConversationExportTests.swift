import Foundation
import UIKit
import ImageIO

/// Compiled into simulator builds only and entered by explicit DEBUG launch flags.
@MainActor enum ConversationExportTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func fixture() -> ConversationExportSnapshot {
        let model = ModelDescriptor.all.first { $0.id == "anime-vita" }!
        let lines: [(String, String)] = [
            ("assistant", "这句在选择范围之前，不应该出现在分享图里。"),
            ("user", "今天有点累，想找个安静的地方。"),
            ("assistant", "那就先在这里坐一会儿吧。晚风很轻，你不用急着把所有事情说清楚。"),
            ("user", "如果今天没做成什么，也没关系吗？"),
            ("assistant", "当然。你已经认真走过今天了。休息不是把时间弄丢，是把自己慢慢找回来。"),
            ("user", "那陪我听一首歌吧。🌙"),
            ("assistant", "好呀。把声音调轻一点，今晚我们只负责好好呼吸。\n等你想说话的时候，我一直在听。"),
            ("user", "明天，我们去看日出。"),
            ("assistant", "约好啦。到时候我会把第一束暖光留给你。"),
            ("assistant", "这句在选择范围之后，不应该出现在分享图里。")
        ]
        return .init(characterID: model.id, characterName: "小光",
                     portraitPNG: (UIImage(named: model.thumbnail + "Portrait") ?? UIImage(named: model.thumbnail))?.pngData(),
                     messages: lines.enumerated().map { index, value in
            CompanionMessage(role: value.0, text: value.1, date: Date(timeIntervalSince1970: 1_790_680_800 + Double(index) * 60))
        })
    }
    static func run() async throws -> String {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ text: String) throws {
            checks += 1; if !condition() { throw Failure(description: text) }
        }
        let snapshot = fixture()
        var range = ConversationExportRange(total: snapshot.messages.count, recent: 3)
        try expect(range.lower == 7 && range.upper == 9 && range.count == 3, "Recent range")
        range.setStart(1); range.setEnd(6)
        let selected = try range.selected(from: snapshot)
        try expect(selected.map(\.id) == Array(snapshot.messages[1...6]).map(\.id), "Inclusive endpoints and order")
        try expect(selected.allSatisfy { !$0.text.contains("不应该") }, "Outside-range content excluded")
        range.setStart(9); try expect(range.count == 1 && range.upper == 9, "Forward crossing collapses range")
        range.setEnd(2); try expect(range.count == 1 && range.lower == 2, "Backward crossing collapses range")
        range.setStart(-100); range.setEnd(100); try expect(range.count == 10, "Bounds clamped")
        let empty = ConversationExportSnapshot(characterID: "other", characterName: "另一个角色", portraitPNG: nil,
            messages: [CompanionMessage(role: "system", text: "PRIVATE SYSTEM"), CompanionMessage(role: "assistant", text: " \n ")])
        try expect(empty.messages.isEmpty, "Filter system/blank entries")
        do { _ = try range.selected(from: empty); throw Failure(description: "Mismatched snapshot accepted") }
        catch is ConversationExportError { checks += 1 }
        do { _ = try ConversationExportRange(total: 0).selected(from: empty); throw Failure(description: "Empty accepted") }
        catch is ConversationExportError { checks += 1 }
        let unicode = "中文 English 👨‍👩‍👧‍👦 e\u{301} 🌙\n第二行\n\n" + String(repeating: "连续没有空格的文字", count: 800)
        let long = ConversationExportSnapshot(characterID: "long", characterName: "长对话", portraitPNG: nil,
            messages: [CompanionMessage(role: "user", text: "开始"), CompanionMessage(role: "assistant", text: unicode), CompanionMessage(role: "user", text: "结束")])
        let plan = try ConversationImageLayout.plan(long.messages, pageHeight: 800)
        try expect(plan.count > 3, "Long single message splits across pages")
        for page in plan {
            try expect(page.height <= 800 && !page.blocks.isEmpty, "Bounded nonempty page")
            for (index, block) in page.blocks.enumerated() {
                try expect(block.y + block.height + ConversationImageLayout.footerHeight <= page.height, "No footer overlap")
                if index > 0 { try expect(page.blocks[index - 1].y + page.blocks[index - 1].height <= block.y, "No message overlap") }
            }
        }
        for index in long.messages.indices {
            let source = long.messages[index].text as NSString
            let lines = plan.flatMap(\.blocks).filter { $0.messageIndex == index }.flatMap(\.lines)
            let restored = lines.map { source.substring(with: $0) }.joined()
            try expect(restored == long.messages[index].text, "Unicode/newline continuity \(index)")
            try expect(lines.first?.location == 0 && NSMaxRange(lines.last!) == source.length, "Complete UTF16 range \(index)")
            for pair in zip(lines, lines.dropFirst()) { try expect(NSMaxRange(pair.0) == pair.1.location, "No missing or duplicated characters") }
        }
        do { _ = try ConversationImageLayout.plan([], pageHeight: 800); throw Failure(description: "Empty render accepted") }
        catch is ConversationExportError { checks += 1 }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ConversationExportQA")
        try? FileManager.default.removeItem(at: root)
        range.setStart(1); range.setEnd(6)
        var evidence: [[String: Any]] = []
        for style in ConversationImageStyle.allCases {
            let result = try await ConversationImageExporter.shared.export(snapshot: snapshot, range: range,
                options: ConversationExportOptions(style: style, showsDates: style == .paper), root: root)
            try expect(result.pages.count == 1 && result.messageCount == 6, "Typical range yields one image")
            for page in result.pages {
                let source = CGImageSourceCreateWithURL(page.imageURL as CFURL, nil)!
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
                try expect(properties[kCGImagePropertyPixelWidth] as? Int == 1080, "1080px independent of screen")
                try expect(properties[kCGImagePropertyPixelHeight] as? Int == page.height && page.height <= 12000, "PNG dimensions")
                try expect(CGImageSourceGetType(source) as String? == "public.png", "Lossless PNG type")
                try expect(properties[kCGImagePropertyGPSDictionary] == nil, "No location metadata")
                try expect(FileManager.default.fileExists(atPath: page.previewURL.path), "Separate small preview")
                evidence.append(["style": style.rawValue, "image": page.imageURL.path, "width": page.width, "height": page.height, "messages": result.messageCount])
            }
        }
        let multipage = try await ConversationImageExporter.shared.export(snapshot: long, range: .init(total: 3, recent: 3), options: .init(), root: root)
        try expect(multipage.pages.count > 1, "Physical multi-image export")
        try expect(multipage.pages.allSatisfy { $0.height <= 12000 }, "Every output fits pixel budget")
        // Cancel only after the exporter has made its own working directory.
        let cancelRoot = root.appendingPathComponent("cancellation")
        let cancel = Task {
            try await ConversationImageExporter.shared.export(snapshot: long, range: .init(total: 3, recent: 3), options: .init(), root: cancelRoot) { _, _ in
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        try await Task.sleep(for: .milliseconds(100)); cancel.cancel()
        do { _ = try await cancel.value; throw Failure(description: "Cancelled export succeeded") }
        catch is CancellationError { checks += 1 }
        try expect((try? FileManager.default.contentsOfDirectory(atPath: cancelRoot.path).isEmpty) == true, "Cancelled partial files removed")
        let data = try JSONSerialization.data(withJSONObject: ["checks": checks, "samples": evidence, "multipageCount": multipage.pages.count], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("result.json"), options: .atomic)
        return "PASS: \(checks) export checks · range, Unicode, pagination, PNG, cancellation"
    }
}
