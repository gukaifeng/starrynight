import CryptoKit
import Foundation
import NaturalLanguage
import SwiftUI

struct TranslationSegment: Codable, Sendable, Equatable {
    let id: String
    let kind: String
    let text: String
}
struct MessageTranslation: Codable, Sendable {
    let sourceFingerprint: String
    let targetLanguage: String
    let segments: [TranslationSegment]
    var lookup: [String:String] { Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0.text) }) }
}
struct TranslationResponse: Decodable, Sendable {
    let targetLanguage: String
    let segments: [TranslationSegment]
}

@MainActor enum ReplyTranslation {
    private static let detection = NSCache<NSString,NSNumber>()
    static func segments(_ message: CompanionMessage) -> [TranslationSegment] {
        guard let script = message.aiScript else {
            return message.text.isEmpty ? [] : [.init(id:"text",kind:"dialogue",text:message.text)]
        }
        return script.beats.flatMap { beat -> [TranslationSegment] in
            if let parts = beat.parts {
                return parts.enumerated().filter { $0.element.isVisible }.map {
                    .init(id:beat.beatId + ".part.\($0.offset)",kind:$0.element.kind,text:$0.element.text)
                }
            }
            var result = beat.narrations.enumerated().filter { $0.element.isVisible }.map {
                TranslationSegment(id:beat.beatId + ".narration.\($0.offset)",kind:"narration",text:$0.element.text)
            }
            if let thought = beat.visibleThought { result.append(.init(id:beat.beatId + ".thought",kind:"thought",text:thought)) }
            if let dialogue = beat.dialogue, !dialogue.text.isEmpty { result.append(.init(id:beat.beatId + ".dialogue",kind:"dialogue",text:dialogue.text)) }
            return result
        }
    }
    static func fingerprint(_ segments: [TranslationSegment]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data:(try? encoder.encode(segments)) ?? Data()).map { String(format:"%02x",$0) }.joined()
    }
    static func needed(_ segments: [TranslationSegment], target: AppLanguage) -> Bool {
        let key=(fingerprint(segments)+target.rawValue) as NSString
        if let result=detection.object(forKey:key) {return result.boolValue}
        let result=segments.contains { needsTranslation($0.text,target:target) }
        detection.countLimit=500;detection.setObject(NSNumber(value:result),forKey:key)
        return result
    }
    private static func needsTranslation(_ text:String,target:AppLanguage) -> Bool {
        guard text.unicodeScalars.contains(where:CharacterSet.letters.contains) else { return false }
        let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return false }
        if language == .simplifiedChinese || language == .traditionalChinese {
            if target == .english { return true }
            // Shared Han characters aren't a mismatch. Convert only when the
            // two Chinese writing systems actually differ for this message.
            let transform = StringTransform(target == .traditional ? "Hans-Hant" : "Hant-Hans")
            return text.applyingTransform(transform,reverse:false).map { $0 != text } ?? false
        }
        return language.rawValue != target.rawValue
    }
    static func convertChinese(_ segments:[TranslationSegment],to target:AppLanguage) -> [TranslationSegment]? {
        guard target != .english,segments.allSatisfy({
            let language=NLLanguageRecognizer.dominantLanguage(for:$0.text)
            return language == .simplifiedChinese || language == .traditionalChinese || language == nil
        }) else {return nil}
        let transform=StringTransform(target == .traditional ? "Hans-Hant" : "Hant-Hans")
        return segments.map {.init(id:$0.id,kind:$0.kind,text:$0.text.applyingTransform(transform,reverse:false) ?? $0.text)}
    }
}

extension CompanionSession {
    func translate(_ message: CompanionMessage, to language: AppLanguage) async throws -> MessageTranslation {
        let segments = ReplyTranslation.segments(message)
        let fingerprint = ReplyTranslation.fingerprint(segments)
        if let saved = message.translations?[language.rawValue], saved.sourceFingerprint == fingerprint { return saved }
        let owner = store.accountID
        let response:TranslationResponse
        if let converted=ReplyTranslation.convertChinese(segments,to:language) {
            response=TranslationResponse(targetLanguage:language.rawValue,segments:converted)
        } else {
            if let script=message.aiScript,script.openingID != nil {
                // A bundled introduction may still be speaking, before the
                // normal preparation task has registered it on the gateway.
                try await api.registerOpening(script,resetID:record.conversationResetID ?? "")
            }
            response = try await api.translate(messageID:message.id,segments:segments,to:language)
        }
        guard response.targetLanguage == language.rawValue,
              response.segments.map(\.id) == segments.map(\.id),
              response.segments.map(\.kind) == segments.map(\.kind),
              response.segments.allSatisfy({ !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }) else { throw AIConnectionError.remote("TRANSLATION_SHAPE_INVALID") }
        let translated = MessageTranslation(sourceFingerprint:fingerprint,targetLanguage:language.rawValue,segments:response.segments)
        guard store.accountID == owner,
              let current = store.record(model.id).messages.first(where: { $0.id == message.id }),
              ReplyTranslation.fingerprint(ReplyTranslation.segments(current)) == fingerprint else { throw CancellationError() }
        store.update(model.id) { record in
            guard let index = record.messages.firstIndex(where: { $0.id == message.id }) else { return }
            if record.messages[index].translations == nil { record.messages[index].translations = [:] }
            record.messages[index].translations?[language.rawValue] = translated
        }
        return translated
    }
}

struct TranslatableReplyContent: View {
    let session: CompanionSession
    let message: CompanionMessage
    let fontSize: CGFloat
    @State private var showingTranslation = false
    @State private var pending = false
    @State private var failed = false
    @State private var request: Task<Void,Never>?
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.resolve(locale.identifier,preferredLanguages:[locale.identifier]) }
    private var segments: [TranslationSegment] { ReplyTranslation.segments(message) }
    private var source: String { ReplyTranslation.fingerprint(segments) }
    private var saved: MessageTranslation? {
        let value = message.translations?[language.rawValue]
        return value?.sourceFingerprint == source ? value : nil
    }
    var body: some View {
        VStack(alignment:.leading,spacing:3) {
            AIReplyContent(message:message,fontSize:fontSize,reveal:session.replyReveal,
                translation:showingTranslation ? saved?.lookup ?? [:] : [:])
            if ReplyTranslation.needed(segments,target:language) {
                HStack(spacing:5) {
                    Spacer(minLength:10)
                    Button(action:toggle) {
                        HStack(spacing:4) {
                            if pending { ProgressView().controlSize(.mini).scaleEffect(0.72).frame(width:12,height:12) }
                            else { Image(systemName:showingTranslation ? "arrow.uturn.backward" : "translate").font(.system(size:10,weight:.medium)) }
                            Text(showingTranslation ? "原文" : failed ? "重试翻译" : "翻译")
                                .font(.system(size:10,weight:.medium))
                        }.foregroundStyle(Theme.secondary.opacity(0.85)).padding(.leading,10).frame(minHeight:32)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(pending || (session.generating && session.record.messages.last?.id == message.id))
                        .accessibilityIdentifier("translate-" + message.id.uuidString)
                        .conversationHitRegion(.control,id:"translate-" + message.id.uuidString)
                }.padding(.bottom,-6)
                if failed { Text("翻译暂时不可用，原文已保留。").font(.system(size:10)).foregroundStyle(Theme.secondary).frame(maxWidth:.infinity,alignment:.trailing) }
            }
        }.onChange(of:language) { reset() }
            .onChange(of:source) { reset() }
            .onDisappear { request?.cancel(); request=nil; pending=false }
    }
    private func reset() { request?.cancel(); request=nil; showingTranslation=false; pending=false; failed=false }
    private func toggle() {
        if showingTranslation { showingTranslation=false; return }
        if saved != nil { showingTranslation=true; return }
        pending=true; failed=false
        let target=language
        request=Task { @MainActor in
            do { _ = try await session.translate(message,to:target); try Task.checkCancellation(); showingTranslation=true }
            catch is CancellationError { return }
            catch { failed=true }
            pending=false; request=nil
        }
    }
}
