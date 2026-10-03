@preconcurrency import ActivityKit
import Observation
import UIKit

struct ConversationIslandSnapshot: Equatable, Sendable {
    var attributes:ConversationActivityAttributes
    var state:ConversationActivityAttributes.ContentState
    static func ==(lhs:Self,rhs:Self)->Bool {
        lhs.attributes.turnID==rhs.attributes.turnID && lhs.attributes.characterID==rhs.attributes.characterID && lhs.state==rhs.state
    }
}

@MainActor protocol ConversationIslandSink:AnyObject {
    var authorized:Bool {get}
    func display(_ snapshot:ConversationIslandSnapshot) async throws
    func end() async
}

/// Only the widget lifecycle uses ActivityKit. The main-thread frame loop never
/// sends activity updates: phases, beats and known duration changes are enough.
@MainActor final class ActivityKitIslandSink:ConversationIslandSink {
    private var activity:Activity<ConversationActivityAttributes>?
    private var suppressedTurn:String?
    var authorized:Bool {ActivityAuthorizationInfo().areActivitiesEnabled}
    func display(_ snapshot:ConversationIslandSnapshot) async throws {
        let identity=snapshot.attributes.turnID
        if let current=activity,[.ended,.dismissed].contains(current.activityState) {
            suppressedTurn=current.attributes.turnID;activity=nil
        }
        guard authorized,suppressedTurn != identity else {
            ConversationLiveActivity.debug("skipped",["authorized":String(authorized),"dismissed":String(suppressedTurn==identity)]);return
        }
        let stale:Date
        switch snapshot.state.phase {
        case .thinking:stale=Date().addingTimeInterval(90)
        case .speaking:stale=(snapshot.state.playbackEnd ?? Date()).addingTimeInterval(15)
        case .ready,.paused:stale=Date().addingTimeInterval(30)
        }
        let content=ActivityContent(state:snapshot.state,staleDate:stale,relevanceScore:80)
        if let current=activity,current.attributes.turnID==identity {
            await current.update(content)
        } else {
            if let current=activity {await current.end(nil,dismissalPolicy:.immediate);activity=nil}
            guard UIApplication.shared.applicationState == .active else {
                ConversationLiveActivity.debug("creationNotForeground");return
            }
            activity=try Activity.request(attributes:snapshot.attributes,content:content,pushType:nil)
            ConversationLiveActivity.debug("requested",["activity":activity?.id ?? ""])
        }
    }
    func end() async {
        let old=activity;activity=nil
        if let old {await old.end(nil,dismissalPolicy:.immediate)}
    }
    static func removeOrphans() async {
        // Snapshot existing activities before awaiting; never remove a newly
        // started turn while startup cleanup is in flight.
        let old=Activity<ConversationActivityAttributes>.activities
        for activity in old {await activity.end(nil,dismissalPolicy:.immediate)}
    }
}

@MainActor @Observable final class ConversationLiveActivity {
    static let shared=ConversationLiveActivity()
    static let enabledKey="starry.conversation.island.enabled.v1"
    static let previewKey="starry.conversation.island.preview.v1"
    static let completionLinger=12.0
    var enabled:Bool {didSet {defaults.set(enabled,forKey:Self.enabledKey);refreshPreferences()}}
    var showsPreview:Bool {didSet {defaults.set(showsPreview,forKey:Self.previewKey);refreshPreferences()}}
    private(set) var lastError:String?
    private(set) var displayedPhase:String?
    @ObservationIgnored private let defaults:UserDefaults
    @ObservationIgnored private let sink:any ConversationIslandSink
    @ObservationIgnored private let testAllowed:Bool
    @ObservationIgnored private var latest:ConversationIslandSnapshot?
    @ObservationIgnored private var retiredTurn:String?
    @ObservationIgnored private var pending:Pending?
    @ObservationIgnored private var worker:Task<Void,Never>?
    @ObservationIgnored private var finishTask:Task<Void,Never>?
    private enum Pending {case show(ConversationIslandSnapshot),end}
    private var allowed:Bool {
        enabled && testAllowed
    }
    var systemEnabled:Bool {sink.authorized}
    init(defaults:UserDefaults = .standard,sink:(any ConversationIslandSink)?=nil) {
        self.defaults=defaults;self.sink=sink ?? ActivityKitIslandSink()
        let args=ProcessInfo.processInfo.arguments
        testAllowed = !args.contains("--ui-testing") || args.contains("--live-activity-fixture")
        enabled=defaults.object(forKey:Self.enabledKey) as? Bool ?? true
        showsPreview=defaults.bool(forKey:Self.previewKey)
    }
    func show(turn:UUID,model:ModelDescriptor,phase:ConversationActivityAttributes.ContentState.Phase,
              text:String?=nil,emotion:String="neutral",messageID:String?=nil,duration:Double?=nil) {
        let identity=turn.uuidString
        guard identity != retiredTurn else {return}
        let previous=latest?.attributes.turnID==identity ? latest?.state : nil
        let playing=phase == .speaking
        let start=playing ? (previous?.phase == .speaking ? previous?.playbackStart : Date()) : nil
        let end=playing ? start?.addingTimeInterval(min(180,max(0.5,duration ?? 8))) : nil
        let state=ConversationActivityAttributes.ContentState(phase:phase,language:AppLanguageSettings.shared.resolved.rawValue,
            emotion:emotion,preview:showsPreview ? text.map {String($0.prefix(90))} : nil,
            playbackStart:start,playbackEnd:end,messageID:messageID)
        let value=ConversationIslandSnapshot(attributes:.init(version:1,turnID:identity,characterID:model.id,
            characterName:String(model.name.prefix(28)),avatarAsset:"Avatar_"+model.runtimeID.replacingOccurrences(of:"-",with:"_")),state:state)
        if latest==value {return}
        latest=value
        Self.debug("phase",["phase":phase.rawValue,"turn":identity,"allowed":String(allowed)])
        finishTask?.cancel();finishTask=nil
        if allowed {enqueue(.show(value))}
        if phase == .ready || phase == .paused {
            finishTask=Task { @MainActor [weak self] in
                do {try await Task.sleep(for:.seconds(Self.completionLinger))} catch {return}
                guard let self,self.latest?.attributes.turnID==identity else {return}
                self.end(turn:turn)
            }
        }
    }
    func end(turn:UUID?=nil) {
        Self.debug("end",["matches":String(turn==nil || latest?.attributes.turnID==turn?.uuidString)])
        if let turn,latest?.attributes.turnID != turn.uuidString {return}
        retiredTurn=latest?.attributes.turnID
        finishTask?.cancel();finishTask=nil;latest=nil
        enqueue(.end)
    }
    private func refreshPreferences() {
        guard allowed else {enqueue(.end);return}
        if var value=latest {
            // Enabling previews never retrospectively exposes an old sentence.
            if !showsPreview {value.state.preview=nil;latest=value}
            enqueue(.show(value))
        }
    }
    private func enqueue(_ value:Pending) {
        pending=value
        guard worker==nil else {return}
        worker=Task { @MainActor [weak self] in
            guard let self else {return}
            while let next=self.pending {
                self.pending=nil
                do {
                    switch next {
                    case .show(let value):
                        if self.allowed {try await self.sink.display(value);self.displayedPhase=value.state.phase.rawValue}
                        else {await self.sink.end();self.displayedPhase=nil}
                    case .end:await self.sink.end();self.displayedPhase=nil
                    }
                    self.lastError=nil
                } catch {self.lastError=String(describing:error)}
            }
            self.worker=nil
        }
    }
    func settle() async {await worker?.value}
    static func debug(_ event:String,_ fields:[String:String]=[:]) {
#if DEBUG && targetEnvironment(simulator)
        guard fixtureLogEnabled else {return}
        let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("island-check-events.jsonl")
        let row:[String:Any]=["event":event,"time":ProcessInfo.processInfo.systemUptime,"fields":fields]
        guard var data=try? JSONSerialization.data(withJSONObject:row,options:.sortedKeys) else {return};data.append(10)
        if let handle=try? FileHandle(forWritingTo:file) {defer {try? handle.close()};try? handle.seekToEnd();try? handle.write(contentsOf:data)}
        else {try? data.write(to:file)}
#endif
    }
#if DEBUG && targetEnvironment(simulator)
    private static let fixtureLogEnabled=ProcessInfo.processInfo.arguments.contains("--live-activity-fixture")
#endif
}
