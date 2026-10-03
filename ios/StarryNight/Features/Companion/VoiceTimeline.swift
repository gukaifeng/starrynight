import Foundation
import Observation

struct VoiceSpan: Codable, Identifiable, Sendable {
    var id: String { "\(name):\(startMs):\(beatId ?? "")" }
    var name: String
    var startMs: Double
    var durationMs: Double
    var beatId: String? = nil
    var bytes: Int? = nil
    var status: String? = nil
    var model: String? = nil
    var audioDurationMs: Double? = nil
    var attempt:Int? = nil
}
enum VoiceTraceValue: Codable, Sendable {
    case text(String), number(Double), boolean(Bool), null
    init(from decoder:Decoder) throws {
        let value=try decoder.singleValueContainer()
        if value.decodeNil() {self = .null}
        else if let v=try? value.decode(Bool.self) {self = .boolean(v)}
        else if let v=try? value.decode(Double.self) {self = .number(v)}
        else {self = .text(try value.decode(String.self))}
    }
    func encode(to encoder:Encoder) throws {
        var value=encoder.singleValueContainer()
        switch self {case .text(let v):try value.encode(v);case .number(let v):try value.encode(v);case .boolean(let v):try value.encode(v);case .null:try value.encodeNil()}
    }
    var label:String {switch self {case .text(let v):v;case .number(let v):String(v);case .boolean(let v):v ? "是" : "否";case .null:"—"}}
}
struct VoiceServerTrace: Codable, Sendable {
    var schemaVersion:Int
    var traceId:String
    var kind:String
    var requestId:String
    var character:String
    var created:Double
    var status:String
    var totalMs:Double
    var gateway:[String:Double]
    var marks:[String:Double]
    var flags:[String:VoiceTraceValue]
    var spans:[VoiceSpan]
    var droppedSpans:Int
}
struct VoiceRecord: Codable, Identifiable, Sendable {
    var id:String
    var account:String
    var character:String
    var kind:String
    var message:String
    var created:Date
    var status:String = "running"
    var totalMs:Double = 0
    var marks:[String:Double] = [:]
    var flags:[String:String] = [:]
    var spans:[VoiceSpan] = []
    var server:VoiceServerTrace? = nil
    var droppedSpans:Int = 0
    var processingMs:Double? {marks["processing_complete"] ?? marks["network_complete"] ?? marks["reply_complete"]}
    var outputSuppressed:Bool {flags["playback"]=="静音" || flags["playback"]=="页面不可见"}
}

/// Content-free diagnostics; audio/headers/dialogue are never written here.
/// Serial utility writes keep tracing I/O off the playback thread. Every timing
/// is local monotonic elapsed time; server clock offsets are never subtracted.
@MainActor @Observable final class VoiceTimeline {
    static let shared=VoiceTimeline()
    private(set) var records:[VoiceRecord] = []
    @ObservationIgnored private var origins:[String:Double] = [:]
    @ObservationIgnored private let queue=DispatchQueue(label:"app.starry.voice-traces",qos:.utility)
    @ObservationIgnored private let file:URL
    @ObservationIgnored private var pending:Task<Void,Never>?
    @ObservationIgnored private var loaded=false
    init(directory:URL? = nil) {
        let folder=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VoiceDiagnostics-v1")
        file=folder.appendingPathComponent("traces.json")
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var url=folder;var values=URLResourceValues();values.isExcludedFromBackup=true;try? url.setResourceValues(values)
        let target=file
        queue.async { [weak self] in
            var saved:[VoiceRecord]=[]
            if let bytes=try? Data(contentsOf:target),bytes.count<=16*1024*1024,
               let decoded=try? JSONDecoder().decode([VoiceRecord].self,from:bytes) {
                saved=Array(decoded.suffix(200)).map {record in
                    var record=record;if record.status=="running" {record.status="interrupted"};return record
                }
            }
            let restored=saved
            Task { @MainActor [weak self] in
                guard let self else {return}
                let ids=Set(records.map(\.id))
                records=Array((restored.filter {!ids.contains($0.id)}+records).suffix(200))
                loaded=true;persist()
            }
        }
    }
    @discardableResult func begin(account:String,character:String,kind:String,message:String="",id:String=UUID().uuidString.lowercased())->String {
        origins[id]=ProcessInfo.processInfo.systemUptime
        records.append(VoiceRecord(id:id,account:account,character:character,kind:kind,message:message,created:Date()))
        if records.count>200 {let old=records.removeFirst();origins[old.id]=nil}
        persist();return id
    }
    func now(_ id:String)->Double {max(0,(ProcessInfo.processInfo.systemUptime-(origins[id] ?? ProcessInfo.processInfo.systemUptime))*1000)}
    private func change(_ id:String,_ apply:(inout VoiceRecord)->Void) {
        guard let index=records.lastIndex(where:{$0.id==id}) else {return}
        apply(&records[index]);records[index].totalMs=max(records[index].totalMs,now(id));persist()
    }
    func mark(_ id:String?,_ name:String,once:Bool=true) {
        guard let id else {return};let time=now(id)
        change(id) {if !once || $0.marks[name]==nil {$0.marks[name]=time}}
    }
    func flag(_ id:String?,_ name:String,_ value:String) {guard let id else {return};change(id) {$0.flags[name]=value}}
    func span(_ id:String?,_ name:String,start:Double,beat:String?=nil,bytes:Int?=nil) {
        guard let id else {return};let duration=max(0,now(id)-start)
        add(id,VoiceSpan(name:name,startMs:start,durationMs:duration,beatId:beat,bytes:bytes))
    }
    func add(_ id:String,_ value:VoiceSpan) {
        change(id) {if $0.spans.count<1024 {$0.spans.append(value)} else {$0.droppedSpans+=1}}
    }
    func receive(_ id:String,event:AIEvent) {
        if let trace=event.trace {change(id) {$0.server=trace}}
        if let message=event.script?.messageId ?? event.messageId {change(id) {$0.message=message}}
        if event.type=="reply.narration.ready" {
            mark(id,"text_received")
            flag(id,"prepared",event.prepared==true ? (event.preparationInflight==true ? "接管未完成的预生成" : "已就绪缓存") : "未命中")
            flag(id,"preparation_inflight",event.preparationInflight==true ? "仍在生成" : "否")
        }
        if event.type=="segment.audio.chunk" {mark(id,"first_audio_received");mark(id,"last_audio_received",once:false)}
        if event.type=="reply.completed" {mark(id,"reply_complete")}
        if event.type=="reply.visuals.updated" {mark(id,"visuals_received",once:false)}
        if event.type=="segment.audio.ready" {mark(id,"audio_ready",once:false)}
        if event.type=="audio.error" || event.type=="reply.error" {flag(id,"error_event",event.type)}
    }
    func finish(_ id:String?,status:String="completed") {
        guard let id else {return};change(id) {if $0.status=="running" {$0.status=status}}
    }
    func clear() {records=[];origins=[:];persist()}
    private func persist() {
        guard loaded else {return}
        pending?.cancel()
        pending=Task { @MainActor [weak self] in
            do {try await Task.sleep(for:.milliseconds(350))} catch {return}
            guard let self else {return};let snapshot=records;let target=file
            queue.async {
                var kept=snapshot
                while let bytes=try? JSONEncoder().encode(kept) {
                    if bytes.count<=16*1024*1024 {try? bytes.write(to:target,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]);break}
                    guard !kept.isEmpty else {break};kept.removeFirst()
                }
            }
        }
    }
}

enum VoiceStage {
    static func title(_ key:String)->String {
        let names=["request.encode":"请求编码","http.headers_wait":"等待响应流可读取（含首事件生成）","network.stream":"响应流持续时间（含生成等待）",
            "sse.decode":"SSE 解码","sse.consume":"事件分发","audio.queue_wait":"客户端分段排队",
            "audio.previous_drain":"等待上一段播放结束","audio.session":"激活音频会话","audio.engine":"创建并启动音频引擎",
            "audio.base64":"音频 Base64 解码","audio.pcm_convert":"PCM 格式转换","audio.schedule":"提交播放缓冲",
            "audio.cache_write":"持久语音缓存写入","audio.cache_read":"持久语音缓存读取","audio.drain":"等待扬声器播放完成",
            "microphone.permission":"麦克风权限","microphone.engine":"麦克风引擎启动","asr.socket_ready":"等待识别服务就绪",
            "first_output":"首次检测到音频输出","first_audio_received":"首个音频到达","text_received":"回复文字到达",
            "model_first_token":"模型首 token","first_sentence_validated":"首句校验就绪","core_generation_completed":"核心生成完成",
            "context.load":"加载上下文","preparation.claim":"检查预缓存","preparation.yield_to_foreground":"等待后台任务让出资源",
            "conversation.visual_dispatch":"客户端表情与动作分派","visuals_received":"表演计划到达","visuals_dispatched":"首组表情与动作分派",
            "conversation.opening_prepare":"准备内置开场","processing_complete":"请求处理完成（不含播放）","audio_ready":"完整语音段就绪",
            "unity.performance_ack":"Unity 表现指令确认（含跨桥排队）","unity.performance_control":"Unity 控制校验与表现选择计算","unity_performance_applied":"Unity 首次接受表现",
            "preparation.priority_queue":"预生成优先级排队","plan.quality_review":"语言与去重检查","reply.commit":"保存对话与关系",
            "tts.generate":"语音模型生成","audio.cache_lookup":"服务端缓存检查","audio.ordered_queue_wait":"服务端分段顺序排队",
            "audio.base64_encode":"服务端音频编码","audio.cache_write_and_trim":"服务端缓存写入与整理"]
        if let title=names[key] {return title}
        let network=["network.dns":"DNS 解析","network.tcp":"TCP 连接（含 TLS 时可能重叠）","network.tls":"TLS 握手","network.upload":"上传请求","network.response_wait":"等待服务器首个响应","network.download":"响应流持续时间（含生成等待）","conversation.prepare_request":"整理对话与请求","conversation.register_opening":"注册内置首句上下文"]
        if let title=network[key] {return title}
        let purpose=key.contains(".suggestions") ? "接话预测" : key.contains(".performance") ? "表演规划" : key.contains(".tts") ? "语音模型" : "对话模型"
        if key == "model.plan.stream" {return "对话模型流式生成"}
        if key.hasPrefix("model.") {
            if key.hasSuffix(".http") {return purpose+"请求（含网络与推理）"}
            if key.hasSuffix(".json_decode") {return purpose+" JSON 解码"}
            if key.hasSuffix(".schema_validate") {return purpose+"结构校验"}
            return "结构化模型调用总时长"
        }
        if key.hasPrefix("provider.") {
            for (suffix,label) in [("connect_tcp","TCP / DNS 连接"),("start_tls","TLS 握手"),("send_request_headers","发送请求头"),("send_request_body","发送请求体"),("receive_response_headers","等待响应头"),("receive_response_body","接收响应"),("dispatch_to_transport","请求分派至传输层"),("response_closed","关闭响应流")] {
                if key.hasSuffix(suffix) {return purpose+" · "+label}
            }
        }
        return key
    }
    static func time(_ ms:Double)->String {ms<1000 ? String(format:"%.1f ms",ms) : String(format:"%.3f s",ms/1000)}
}
