import Foundation

/// Read-time repair for legacy text. Nested annotations form one styled region;
/// no closing parenthesis can accidentally return its remainder to speech style.
enum ReplyDisplayText {
    struct Piece:Equatable {let text:String;let aside:Bool}
    struct State {var closers:[Character]=[]}
    static func needsSpeechRepair(_ text:String)->Bool {
        var depth=0
        for c in text {
            if c=="（" || c=="(" {depth+=1}
            if c=="）" || c==")" {depth-=1;if depth<0{return true}}
        }
        return depth != 0 || pieces(text).contains {$0.aside && isDirection($0.text)}
    }
    private static func isDirection(_ text:String)->Bool {
        if text.range(of:"(?:是什么|什么意思|怎么|为什么|是不是|吗[？?]?$)",options:.regularExpression) != nil {return false}
        if text.range(of:"^(?:我|咱)(?:心里|有点|头都|也想|觉得)|^I (?:feel|wonder|hope)\\b",options:[.regularExpression,.caseInsensitive]) != nil {return true}
        let pattern="^(?:(?:她|他|我|角色)\\s*)?(?:(?:轻轻|轻|缓缓|稍稍)\\s*)?(?:语气|语调|动作|心理|心声|心里|心想|露出|神情|微笑|眨眼|点头|摇头|轻翻|翻着|唇角|嘴角|眼神|眼睛变|扶着|扶住|揉着|揉了揉|捂着|捂住|托着|撑着|抱着|抱住|攥着|握着|拉着|抿着|抿了抿|鼓起|撅起|皱着|皱起|蹙眉|偏过头|转过头|垂下|抬起|低下|伸出|收回|靠近|后退|故作|佯装)|^(?:(?:she|he|I)\\s+)?(?:smiles?|blinks?|nods?|waves?|holds?|rubs?|covers?|tilts?|turns?|raises?|lowers?|pretends?|feigns?|frowns?|pouts?)\\b"
        return text.trimmingCharacters(in:.whitespacesAndNewlines).range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil
    }
    static func flatten(_ text:String)->String {
        text.replacingOccurrences(of:"[（）()]",with:"",options:.regularExpression)
            .replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression)
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func pieces(_ text:String)->[Piece] {
        var state=State();return pieces(text,state:&state)
    }
    /// Preserve annotation depth across dialogue fragments; inserted structured
    /// thoughts never close an annotation in the original dialogue field.
    static func repaired(_ parts:[AIReplyPart])->[AIReplyPart] {
        var state=State()
        return parts.map {part in
            guard part.kind=="dialogue" else {return part}
            var value=part
            value.text=pieces(part.text,state:&state).map {$0.aside ? "（"+flatten($0.text)+"）" : $0.text}.joined()
            return value
        }
    }
    private static func pieces(_ text:String,state:inout State)->[Piece] {
        var result:[Piece]=[],buffer="",inside="",closers=state.closers
        let pairs:[Character:Character]=["（":"）","(":")"]
        for character in text {
            if let closer=pairs[character] {
                if closers.isEmpty {
                    if !buffer.isEmpty {result.append(.init(text:buffer,aside:false));buffer=""}
                } else {inside.append(character)}
                closers.append(closer)
            } else if character==closers.last || ((character=="）" || character==")") && !closers.isEmpty) {
                closers.removeLast()
                if closers.isEmpty {result.append(.init(text:flatten(inside),aside:true));inside=""}
                else {inside.append(character)}
            } else if !closers.isEmpty {inside.append(character)}
            else if character=="）" || character==")" {
                // Repair an orphan action continuation, preserving ordinary
                // spoken words while removing an unmatched closing glyph.
                let start=buffer.lastIndex(where:{"\n。！？!?".contains($0)}).map{buffer.index(after:$0)} ?? buffer.startIndex
                let suffix=String(buffer[start...])
                if isDirection(suffix) {
                    let prefix=String(buffer[..<start]);if !prefix.isEmpty {result.append(.init(text:prefix,aside:false))}
                    result.append(.init(text:flatten(suffix),aside:true));buffer=""
                }
            }
            else {buffer.append(character)}
        }
        if !closers.isEmpty {result.append(.init(text:flatten(inside),aside:true))}
        if !buffer.isEmpty {result.append(.init(text:buffer,aside:false))}
        state.closers=closers
        return result.filter{!$0.text.isEmpty}
    }
}
