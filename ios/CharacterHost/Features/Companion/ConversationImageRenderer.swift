import UIKit
import CoreText
import ImageIO

/// Page geometry is expressed in 360-point paper coordinates; export is always
/// 3x (1080 px), independently of the screen or Accessibility text size.
enum ConversationImageLayout {
    static let width: CGFloat = 360
    static let scale: CGFloat = 3
    static let maxHeight: CGFloat = 4000
    static let lineHeight: CGFloat = 22
    static let textWidth: CGFloat = 226
    static let footerHeight: CGFloat = 92
    struct Block: Sendable {
        let messageIndex: Int
        let lines: [NSRange]
        let y: CGFloat
        let continued: Bool
        var height: CGFloat { 78 + CGFloat(lines.count) * lineHeight }
    }
    struct Page: Sendable {
        var blocks: [Block] = []
        var height: CGFloat = 0
    }
    static func attributes(color: UIColor = .black) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: 14.5), .foregroundColor: color]
    }
    static func lineRanges(_ text: String) throws -> [NSRange] {
        let string = NSAttributedString(string: text, attributes: attributes())
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        var result: [NSRange] = [], position = 0
        while position < string.length {
            try Task.checkCancellation()
            let length = CTTypesetterSuggestLineBreak(typesetter, position, Double(textWidth))
            guard length > 0 else { throw ConversationExportError.cannotRender }
            result.append(NSRange(location: position, length: length)); position += length
        }
        return result
    }
    static func plan(_ messages: [ConversationExportSnapshot.Message],
                     pageHeight: CGFloat = maxHeight) throws -> [Page] {
        guard !messages.isEmpty else { throw ConversationExportError.emptyRange }
        guard pageHeight >= 700, pageHeight <= maxHeight,
              messages.reduce(0, { $0 + $1.text.utf16.count }) <= 1_000_000 else {
            throw ConversationExportError.tooLarge
        }
        var pages: [Page] = [], page = Page(), y: CGFloat = 310
        func finish() {
            page.height = ceil(y + footerHeight)
            pages.append(page); page = Page(); y = 140
        }
        for (index, message) in messages.enumerated() {
            try Task.checkCancellation()
            let lines = try lineRanges(message.text)
            var cursor = 0
            while cursor < lines.count {
                let fullHeight = 78 + CGFloat(lines.count - cursor) * lineHeight
                let available = pageHeight - footerHeight - y
                // Prefer keeping a message whole. Split only if it cannot fit on
                // an empty page, and then only on CoreText's Unicode line breaks.
                if !page.blocks.isEmpty && fullHeight > available { finish(); continue }
                let capacity = Int((pageHeight - footerHeight - y - 78) / lineHeight)
                guard capacity > 0 else { throw ConversationExportError.cannotRender }
                let count = min(capacity, lines.count - cursor)
                let block = Block(messageIndex: index, lines: Array(lines[cursor..<cursor + count]),
                                  y: y, continued: cursor > 0)
                page.blocks.append(block); y += block.height; cursor += count
                if cursor < lines.count { finish() }
                guard pages.count < 64 else { throw ConversationExportError.tooLarge }
            }
        }
        if !page.blocks.isEmpty { finish() }
        return pages
    }
}

/// Serial background actor: a single page bitmap at a time, autoreleased after
/// encoding. The UI holds file URLs and one small preview, never full-size PNGs.
actor ConversationImageExporter {
    static let shared = ConversationImageExporter()
    static var root: URL { CacheLocations.current.exports }

    func export(snapshot: ConversationExportSnapshot, range: ConversationExportRange,
                options: ConversationExportOptions,
                root: URL = ConversationImageExporter.root,
                progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> ConversationImageResult {
        let messages = try range.selected(from: snapshot)
        let plan = try ConversationImageLayout.plan(messages)
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        // The system share extension may read lazily. Retain completed exports
        // for 24h and clean only this feature's UUID directories on the next use.
        if root.standardizedFileURL == Self.root.standardizedFileURL { await CacheStorage.shared.pruneExports() }
        else { for old in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            guard UUID(uuidString: old.lastPathComponent) != nil,
                  let created = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  created < Date().addingTimeInterval(-86_400) else { continue }
            try? manager.removeItem(at: old)
        } }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lease = root.standardizedFileURL == Self.root.standardizedFileURL ? try await CacheStorage.shared.leaseExport(directory) : nil
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var pages: [ConversationImagePage] = [], bytes = 0
            for (index, page) in plan.enumerated() {
                try Task.checkCancellation()
                await progress(index, plan.count)
                let rendered = try autoreleasepool {
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = ConversationImageLayout.scale; format.opaque = true
                    format.preferredRange = .standard
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 360, height: page.height), format: format)
                    let png = renderer.pngData { context in
                        ConversationImageDrawing.draw(context.cgContext, snapshot: snapshot, messages: messages,
                            page: page, index: index, count: plan.count, options: options)
                    }
                    bytes += png.count
                    guard bytes <= 200_000_000 else { throw ConversationExportError.tooLarge }
                    let url = directory.appendingPathComponent(String(format: "星夜-对话-%02d.png", index + 1))
                    try png.write(to: url, options: .atomic)
                    try Task.checkCancellation()
                    let previewURL = directory.appendingPathComponent("preview-\(index).jpg")
                    guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: max(540, Int(page.height * 1.5)),
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary),
                          let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.9) else {
                        throw ConversationExportError.cannotRender
                    }
                    try jpeg.write(to: previewURL, options: .atomic)
                    return ConversationImagePage(imageURL: url, previewURL: previewURL,
                        width: 1080, height: Int(page.height * 3))
                }
                pages.append(rendered)
            }
            try Task.checkCancellation()
            await progress(plan.count, plan.count)
            return ConversationImageResult(directory: directory, pages: pages, messageCount: messages.count, cacheLease:lease)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }
}

private enum ConversationImageDrawing {
    struct Palette {
        let base, ink, secondary, accent, assistant, user: UIColor
        init(_ style: ConversationImageStyle) {
            if style == .moon {
                base = color(0x11151D); ink = color(0xF3ECE1); secondary = color(0xB4AEA8)
                accent = color(0xDFC7A6); assistant = color(0x202630); user = color(0x332D2B)
            } else {
                base = color(0xF5EFE5); ink = color(0x353C44); secondary = color(0x756D65)
                accent = color(0x92704D); assistant = color(0xFFFBF5); user = color(0xE9DDCA)
            }
        }
    }
    static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static func text(_ string: String, _ rect: CGRect, size: CGFloat, color: UIColor,
                     weight: UIFont.Weight = .regular, serif: Bool = false, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let font = serif ? (UIFont(name: "SongtiSC-Regular", size: size) ?? .systemFont(ofSize: size)) : .systemFont(ofSize: size, weight: weight)
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    static func star(_ context: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
        context.saveGState(); context.setFillColor(color.cgColor)
        context.move(to: CGPoint(x: center.x, y: center.y - radius))
        context.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + radius * 0.16, y: center.y - radius * 0.16))
        context.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + radius * 0.16, y: center.y + radius * 0.16))
        context.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - radius * 0.16, y: center.y + radius * 0.16))
        context.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - radius * 0.16, y: center.y - radius * 0.16))
        context.fillPath(); context.restoreGState()
    }
    static func portrait(_ image: UIImage?, in rect: CGRect, context: CGContext, palette: Palette, name: String) {
        context.saveGState(); UIBezierPath(ovalIn: rect).addClip()
        palette.assistant.setFill(); context.fill(rect)
        if let image, image.size.width > 0, image.size.height > 0 {
            let scale = max(rect.width / image.size.width, rect.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        } else {
            text(String(name.prefix(1)), CGRect(x: rect.minX, y: rect.midY - rect.height * 0.23, width: rect.width, height: rect.height * 0.5),
                 size: rect.height * 0.36, color: palette.ink, alignment: .center)
        }
        context.restoreGState()
    }
    static func line(_ context: CGContext, y: CGFloat, palette: Palette) {
        context.setStrokeColor(palette.accent.withAlphaComponent(0.22).cgColor); context.setLineWidth(0.5)
        context.move(to: CGPoint(x: 26, y: y)); context.addLine(to: CGPoint(x: 334, y: y)); context.strokePath()
    }
    static func date(_ date: Date, time: Bool = false) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = time ? "M月d日 HH:mm" : "yyyy.MM.dd"
        return formatter.string(from: date)
    }
    static func draw(_ context: CGContext, snapshot: ConversationExportSnapshot,
                     messages: [ConversationExportSnapshot.Message], page: ConversationImageLayout.Page,
                     index: Int, count: Int, options: ConversationExportOptions) {
        let palette = Palette(options.style), portraitImage = snapshot.portraitPNG.flatMap(UIImage.init(data:))
        palette.base.setFill(); context.fill(CGRect(x: 0, y: 0, width: 360, height: page.height))
        // Two quiet pools of light give the portrait a setting, with no texture
        // over the actual message text and no screenshot of the private UI.
        for (point, tint, radius) in [(CGPoint(x: 314, y: 117), palette.accent, CGFloat(230)),
                                      (CGPoint(x: 12, y: 250), color(0x729995), CGFloat(180))] {
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [tint.withAlphaComponent(0.16).cgColor, tint.withAlphaComponent(0).cgColor] as CFArray,
                                         locations: [0, 1]) {
                context.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [])
            }
        }
        star(context, center: CGPoint(x: 34, y: 37), radius: 8, color: palette.accent)
        text("星 夜", CGRect(x: 51, y: 27, width: 95, height: 24), size: 14, color: palette.ink, weight: .medium)
        text("对 话 珍 藏", CGRect(x: 239, y: 31, width: 95, height: 20), size: 10, color: palette.secondary, alignment: .right)
        if index == 0 {
            text("与你，留一段时光", CGRect(x: 26, y: 85, width: 308, height: 35), size: 24, color: palette.ink, serif: true)
            text(snapshot.characterName, CGRect(x: 26, y: 145, width: 178, height: 66), size: 24, color: palette.ink, weight: .medium)
            text("AI 角色 · 我们的对话", CGRect(x: 26, y: 217, width: 186, height: 20), size: 11, color: palette.secondary)
            let avatar = CGRect(x: 220, y: 133, width: 104, height: 104)
            context.setStrokeColor(palette.accent.withAlphaComponent(0.5).cgColor); context.setLineWidth(0.7)
            context.strokeEllipse(in: avatar.insetBy(dx: -6, dy: -6))
            portrait(portraitImage, in: avatar, context: context, palette: palette, name: snapshot.characterName)
            star(context, center: CGPoint(x: 323, y: 144), radius: 5, color: palette.accent)
            line(context, y: 263, palette: palette)
            text(options.showsDates ? date(messages[0].date) + " 起" : "那些想留下的话", CGRect(x: 26, y: 277, width: 206, height: 19), size: 10, color: palette.secondary)
        } else {
            portrait(portraitImage, in: CGRect(x: 26, y: 72, width: 38, height: 38), context: context, palette: palette, name: snapshot.characterName)
            text(snapshot.characterName, CGRect(x: 77, y: 73, width: 240, height: 25), size: 17, color: palette.ink, weight: .medium)
            text("接着，上一张的话", CGRect(x: 77, y: 98, width: 240, height: 18), size: 10, color: palette.secondary)
        }
        if index == 0 { text("\(messages.count) 条 · \(index + 1)/\(count)", CGRect(x: 225, y: 277, width: 109, height: 19), size: 10, color: palette.secondary, alignment: .right) }
        for block in page.blocks {
            let message = messages[block.messageIndex], ai = message.role == "assistant"
            let x: CGFloat = ai ? 26 : 76
            let name = ai ? snapshot.characterName : "我"
            let metadata = (block.continued ? " · 续" : "") + (options.showsDates ? " · " + date(message.date, time: true) : "")
            if ai { portrait(portraitImage, in: CGRect(x: x, y: block.y, width: 20, height: 20), context: context, palette: palette, name: name) }
            text(name + metadata, CGRect(x: ai ? x + 28 : x, y: block.y + 3, width: ai ? 230 : 258, height: 18),
                 size: 10, color: palette.secondary, alignment: ai ? .left : .right)
            let rect = CGRect(x: x, y: block.y + 28, width: 258, height: CGFloat(block.lines.count) * ConversationImageLayout.lineHeight + 28)
            (ai ? palette.assistant : palette.user).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 15).fill()
            let string = message.text as NSString
            for (number, range) in block.lines.enumerated() {
                let value = string.substring(with: range)
                let attributed = NSAttributedString(string: value, attributes: ConversationImageLayout.attributes(color: palette.ink))
                let line = CTLineCreateWithAttributedString(attributed)
                context.saveGState()
                context.textMatrix = .identity
                context.translateBy(x: x + 16, y: rect.minY + 14 + CGFloat(number) * ConversationImageLayout.lineHeight + 16)
                context.scaleBy(x: 1, y: -1); context.textPosition = .zero
                CTLineDraw(line, context); context.restoreGState()
            }
        }
        let footerY = page.height - 64
        line(context, y: footerY, palette: palette)
        text("星夜  ·  每一句，都有回声", CGRect(x: 26, y: footerY + 20, width: 260, height: 19), size: 10, color: palette.secondary)
        text(String(format: "%02d / %02d", index + 1, count), CGRect(x: 261, y: footerY + 20, width: 73, height: 19), size: 10, color: palette.secondary, alignment: .right)
    }
}
