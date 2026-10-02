import Foundation

/// Read-time repair for legacy text. Nested annotations form one styled region;
/// no closing parenthesis can accidentally return its remainder to speech style.
enum ReplyDisplayText {
    struct Piece:Equatable {let text:String;let aside:Bool}
    static func flatten(_ text:String)->String {
        text.replacingOccurrences(of:"[（）()]",with:"",options:.regularExpression)
            .replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression)
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func pieces(_ text:String)->[Piece] {
        var result:[Piece]=[],buffer="",inside="",closers:[Character]=[]
        let pairs:[Character:Character]=["（":"）","(":")"]
        for character in text {
            if let closer=pairs[character] {
                if closers.isEmpty {
                    if !buffer.isEmpty {result.append(.init(text:buffer,aside:false));buffer=""}
                } else {inside.append(character)}
                closers.append(closer)
            } else if character==closers.last {
                closers.removeLast()
                if closers.isEmpty {result.append(.init(text:flatten(inside),aside:true));inside=""}
                else {inside.append(character)}
            } else if !closers.isEmpty {inside.append(character)}
            else {buffer.append(character)}
        }
        if !closers.isEmpty {result.append(.init(text:flatten(inside),aside:true))}
        if !buffer.isEmpty {result.append(.init(text:buffer,aside:false))}
        return result.filter{!$0.text.isEmpty}
    }
}
