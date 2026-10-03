#if DEBUG && targetEnvironment(simulator)
import ActivityKit
import SwiftUI

@MainActor private final class IslandRecordingSink:ConversationIslandSink {
    var authorized=true
    var displays:[ConversationIslandSnapshot]=[]
    var ends=0
    func display(_ snapshot:ConversationIslandSnapshot) async throws {displays.append(snapshot)}
    func end() async {ends+=1}
}

@MainActor enum ConversationIslandChecks {
    static func run() async throws->String {
        func require(_ value:Bool,_ why:String) throws {if !value {throw NSError(domain:"IslandChecks",code:1,userInfo:[NSLocalizedDescriptionKey:why])}}
        let suite="starry.island.check.\(UUID())",defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let sink=IslandRecordingSink(),manager=ConversationLiveActivity(defaults:defaults,sink:sink)
        let turn=UUID(),model=ModelDescriptor.defaultCharacter,message=UUID().uuidString
        try require(manager.enabled && !manager.showsPreview,"Default presentation must be enabled and private")
        manager.show(turn:turn,model:model,phase:.thinking,text:"Only shown after consent")
        await manager.settle()
        try require(sink.displays.count==1 && sink.displays[0].state.preview==nil,"Thinking must not expose a conversation by default")
        manager.showsPreview=true;await manager.settle()
        manager.show(turn:turn,model:model,phase:.speaking,text:String(repeating:"a",count:400),emotion:"happy",messageID:message,duration:12)
        await manager.settle()
        let speaking=sink.displays.last!
        try require(speaking.state.preview?.count==90 && speaking.state.playbackEnd!>speaking.state.playbackStart!,"Speaking must have a bounded preview and native timer interval")
        let bytes=try JSONEncoder().encode(speaking.attributes).count+JSONEncoder().encode(speaking.state).count
        try require(bytes<4096,"ActivityKit payload limit exceeded")
        let count=sink.displays.count
        manager.show(turn:turn,model:model,phase:.speaking,text:String(repeating:"a",count:400),emotion:"happy",messageID:message,duration:12)
        await manager.settle()
        try require(sink.displays.count==count,"Frame-identical updates must be coalesced")
        manager.showsPreview=false;await manager.settle()
        try require(sink.displays.last?.state.preview==nil,"Turning off preview must immediately remove text")
        manager.enabled=false;await manager.settle()
        try require(sink.ends>0 && manager.displayedPhase==nil,"Disabling must end the activity")
        manager.enabled=true;await manager.settle()
        manager.show(turn:turn,model:model,phase:.ready,messageID:message);await manager.settle()
        manager.end(turn:UUID());await manager.settle()
        try require(manager.displayedPhase=="ready","An old turn must not end the current turn")
        manager.end(turn:turn);await manager.settle()
        try require(manager.displayedPhase==nil,"Stopping must not leave a pending activity")
        manager.show(turn:turn,model:model,phase:.ready,messageID:message);await manager.settle()
        try require(manager.displayedPhase==nil,"Returning to an ended turn must not recreate the island")
        let url=ConversationActivityAttributes.route(characterID:model.id,messageID:message)!
        let route=ConversationActivityAttributes.decodeRoute(url)
        try require(route?.character==model.id && route?.message?.uuidString.lowercased()==message.lowercased(),"Tap routing must preserve the exact conversation and message")
        try require(ConversationActivityAttributes.decodeRoute(URL(string:"https://example.com/conversation?character=x")!)==nil,"An external scheme cannot select a conversation")
        try require(ConversationIslandCopy.text("ready",language:"en")=="Your reply is here" && ConversationIslandCopy.text("thinking",language:"zh-Hant").contains("怎麼"),"Widget localization must be independent from the host bundle")
        return "PASS: lifecycle, privacy, timer, payload budget, coalescing, stale-turn ownership, exact routing, three languages"
    }
}

struct ConversationIslandFixture:View {
    @State private var turn=UUID()
    @State private var result="Checking…"
    @State private var active=false
    @State private var liveCount=0
    @Bindable private var manager=ConversationLiveActivity.shared
    var body:some View {
        VStack(alignment:.leading,spacing:24) {
            Text("星夜 · 灵动岛").font(.title2.weight(.medium))
            Text(result).font(.caption).accessibilityIdentifier("islandCoreResult")
            Text("ActivityKit: \(liveCount)")
                .accessibilityIdentifier("islandSystemCount")
            Text(manager.lastError ?? manager.displayedPhase ?? "ready").accessibilityIdentifier("islandSystemState")
            Button("预览思考状态") {start(.thinking)}.accessibilityIdentifier("islandStartThinking")
            Button("预览说话状态") {start(.speaking)}.accessibilityIdentifier("islandStartSpeaking")
            Button("回复已到达") {start(.ready)}.accessibilityIdentifier("islandReady")
            Button("结束") {manager.end(turn:turn);active=false}.accessibilityIdentifier("islandEnd")
            Text("这里仅验证系统呈现，不调用 AI，不播放伪装成角色的测试语音。")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
            Spacer()
        }.padding(28).foregroundStyle(.white).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color(red:0.04,green:0.05,blue:0.07))
            .task {
                manager.enabled=true;manager.showsPreview=false
                do {result=try await ConversationIslandChecks.run()} catch {result="FAIL: \(error.localizedDescription)"}
                // ActivityKit acknowledges dismissal asynchronously. Observe
                // real system state rather than an earlier SwiftUI snapshot.
                while !Task.isCancelled {
                    liveCount=Activity<ConversationActivityAttributes>.activities.filter {![.dismissed,.ended].contains($0.activityState)}.count
                    do {try await Task.sleep(for:.milliseconds(200))} catch {return}
                }
            }
    }
    private func start(_ phase:ConversationActivityAttributes.ContentState.Phase) {
        if !active {turn=UUID();active=true}
        manager.show(turn:turn,model:.defaultCharacter,phase:phase,text:"今天的心事，慢慢说也没关系。",emotion:"happy",duration:40)
    }
}
#endif
