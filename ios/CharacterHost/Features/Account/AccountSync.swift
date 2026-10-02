import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Native caches remain usable offline. Durable local records + the last server
/// acknowledgement form a recoverable outbox. A conflict never overwrites local
/// edits: keep both versions and expose explicit resolution in the account page.
@MainActor final class AccountSync {
    private struct Shadow:Codable { var version:Int;var body:JSONValue }
    private struct Remote:Codable { var kind:String;var id:String;var version:Int;var body:JSONValue;var deleted:Bool }
    private struct State:Codable { var schemaVersion:Int?=1;var cursor=0;var hydrated=false;var shadows:[String:Shadow]=[:];var conflicts:[String:Remote]=[:] }
    private let account:AccountStore
    private let store:CompanionStore
    private let library:CharacterLibrary
    private let api:PlatformAPI
    private var state = State()
    private var owner = ""
    private var task:Task<Void,Never>?
    private var running=false
    private var deletionSuspended=false
    var onConversationReset:((String)->Void)?
    func suspendForDeletion() async {
        deletionSuspended=true
        let previous=task;previous?.cancel();await previous?.value
    }
    func resumeAfterDeletion() {deletionSuspended=false;schedule(immediate:true)}
    private var again=false
    private var applying=false
    private var failures=0
    private var catalogRefreshedAt=Date.distantPast
    private var localRevision=0
    private var needsRestore=false
    private var observers:[NSObjectProtocol]=[]
    private let directory:URL
    init(account:AccountStore,store:CompanionStore,library:CharacterLibrary,api:PlatformAPI = .shared,directory:URL? = nil) {
        self.account=account;self.store=store;self.library=library;self.api=api
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("account-sync")
        for name in [Notification.Name.accountDataChanged,.themeChanged] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { guard let self,!self.applying else{return};self.localRevision += 1;self.schedule() }
            })
        }
        account.onSync = { [weak self] in self?.schedule(immediate:true) }
        account.onUseCloud = { [weak self] in self?.resolveConflicts() }
#if canImport(UIKit)
        observers.append(NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.failures=0;self?.schedule(immediate:true) }
        })
#endif
    }
    func activate() {
        task?.cancel()
        needsRestore=true
        let id=account.cloudSession?.user.id ?? ""
        if id != owner {
            owner=id;state=State();failures=0;catalogRefreshedAt = .distantPast
            if !id.isEmpty,let data=try? Data(contentsOf:file),let value=try? JSONDecoder().decode(State.self,from:data){state=value}
        }
        schedule(immediate:true)
    }
    private var file:URL { directory.appendingPathComponent(owner+".json") }
    private func save() throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try JSONEncoder().encode(state).write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    func schedule(immediate:Bool=false) {
        guard !deletionSuspended else {return}
        guard !owner.isEmpty,account.cloudSession?.user.id==owner,store.accountID==owner else{return}
        if running{again=true;return}
        task?.cancel();task=Task { [weak self] in
            if !immediate { do{try await Task.sleep(for:.milliseconds(900))}catch{return} }
            await self?.synchronize()
        }
    }
    private func ensure(_ captured:String)throws{
        try Task.checkCancellation()
        guard captured==owner,store.accountID==owner,account.cloudSession?.user.id==owner else{throw CancellationError()}
    }
    private func call(_ method:String,_ path:String,_ body:JSONValue?=nil) async throws -> JSONValue {
        let captured=owner
        guard let session=account.cloudSession,session.user.id==captured else{throw CancellationError()}
        do {
            let result=try await api.request(method,path,token:session.token,body:body)
            try ensure(captured)
            guard account.cloudSession?.token==session.token else {again=true;throw CancellationError()}
            return result
        } catch {
            try ensure(captured)
            // A password/name change rotates the token while a sync request may
            // still be in flight. Its stale 401 must not sign out the new session.
            if account.cloudSession?.token != session.token {again=true;throw CancellationError()}
            throw error
        }
    }
    private func synchronize() async {
        guard !deletionSuspended else {return}
        guard !store.currentRecords.values.contains(where:{$0.pendingDeletionID != nil}) else {
            account.syncStatus="删除尚未完成 · 请在消息页重试";return
        }
        guard !running else{return};running=true;again=false
        var retryDelay:Double?
        defer {
            running=false
            if again{schedule()}
            else if let retryDelay {
                task=Task { [weak self] in
                    do { try await Task.sleep(for:.seconds(retryDelay)) } catch { return }
                    await self?.synchronize()
                }
            }
        }
        do {
            try ensure(owner);account.syncStatus="正在同步"
            // A restored pre-upgrade Keychain session has no public handle.
            // Fetch identity on activation instead of requiring another login.
            if needsRestore || account.cloudSession?.user.starryId==nil {
                let value=try await call("GET","/v1/me")
                let decoder=JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
                account.updateCloudUser(try decoder.decode(PlatformUser.self,from:JSONEncoder().encode(value)))
            }
            if !state.hydrated {
                if !account.cloudShouldImportLocal {
                    let subscriptions=try await relations("subscriptions"),follows=try await relations("follows")
                    applying=true;library.applyCloudRelations(subscriptions:subscriptions,follows:follows);applying=false
                }
                let settings=try await call("GET","/v1/me/settings")
                try receive(Remote(kind:"settings",id:"settings",version:int(settings,"version"),body:settings.object?["data"] ?? .object([:]),deleted:false),pending:account.cloudShouldImportLocal ? try snapshot():[:])
            }
            while true {
                let page=try await call("GET","/v1/sync?after=\(state.cursor)&limit=100")
                guard case .array(let changes)=page.object?["items"] else{throw PlatformError.invalidResponse}
                // Snapshot after the network await, so edits made while waiting
                // are included in the three-way comparison.
                var pending=try pendingValues();let previous=state
                do {
                    try store.applyCloudBatch {
                        for change in changes {
                            if let remote=normalize(change){
                                try receive(remote,pending:pending)
                                if remote.kind=="conversation_reset",remote.version >= (store.record(remote.id).conversationResetVersion ?? 0) {
                                    let prefixes=["message:","memory:","moment:"].map{$0+remote.id+"/"}
                                    pending=pending.filter{!prefixes.contains(where:$0.key.hasPrefix) && $0.key != "preference:"+remote.id}
                                }
                            }
                            state.cursor=max(state.cursor,int(change,"revision"))
                        }
                    }
                }catch {state=previous;throw error}
                try save()
                if page.object?["next_cursor"]?.string?.isEmpty != false {break}
            }
            state.hydrated=true;account.cloudShouldImportLocal=false;try save()
            try await refreshReferencedCatalog()
            if needsRestore {needsRestore=false;account.onFirstSync?()}
            var local=try snapshot(),snapshotRevision=localRevision
            let keys=Set(local.keys).union(state.shadows.keys).sorted { rank($0)==rank($1) ? $0<$1 : rank($0)<rank($1) }
            for key in keys {
                if state.conflicts[key] != nil {continue}
                // A previous request may have yielded while the user edited.
                if snapshotRevision != localRevision {local=try snapshot();snapshotRevision=localRevision}
                let body=local[key] ?? .null
                guard state.shadows[key]?.body != body,body != .null || removable(key) else{continue}
                let version=state.shadows[key]?.version ?? 0
                let response=try await push(key,body:body,version:version)
                if body == .null{state.shadows.removeValue(forKey:key)}
                else{state.shadows[key]=Shadow(version:max(1,int(response,"version")),body:body)}
                try save();again=true
            }
            state.hydrated=true;account.cloudShouldImportLocal=false;try save()
            failures=0
            account.hasSyncConflicts = !state.conflicts.isEmpty
            account.syncStatus = state.conflicts.isEmpty ? "已同步到服务器" : "有 \(state.conflicts.count) 项冲突，本机改动已保留"
        }catch is CancellationError{}
        catch {
            account.syncStatus="待同步 · 本机资料已保留"
            if case PlatformError.status(401)=error{
                account.needsReauthentication=true;account.syncStatus="登录已过期 · 本机改动已保留"
                account.error="登录已过期，请重新登录；本机改动会保留。";again=false
            }
            else { failures += 1;again=false;if failures<=5 { retryDelay=min(60,pow(2,Double(failures))) } }
        }
    }
    private func pendingValues()throws->[String:JSONValue] {
        let local=try snapshot()
        var pending=local.filter { key,body in
            if let shadow=state.shadows[key] { return shadow.body != body }
            if ["message:","memory:","moment:"].contains(where:key.hasPrefix){return true}
            return state.hydrated || account.cloudShouldImportLocal
        }
        for key in state.shadows.keys where local[key]==nil && removable(key){pending[key] = .null}
        return pending
    }
    private func relations(_ name:String)async throws->[String]{
        var result:[String]=[],cursor=""
        repeat {
            let page=try await call("GET","/v1/me/\(name)?limit=200&after=\(cursor)")
            if case .array(let items)=page.object?["items"]{result += items.compactMap{$0.object?["id"]?.string}}
            cursor=page.object?["next_cursor"]?.string ?? ""
        }while !cursor.isEmpty
        return result
    }
    private func applyCharacter(_ value:JSONValue,id:String,author:String?,owned:Bool) {
        guard var native=value.object?["data"]?.object?["native"]?.object else{return}
        native["id"] = .string(id)
        native["ownerID"] = .string(owned ? owner : "public-author:"+(author ?? "unknown"))
        native["authorID"] = author.map(JSONValue.string) ?? .null
        native["published"] = .bool(value.object?["visibility"]?.string == "public")
        if let base=value.object?["base_id"]{native["baseID"]=base}
        if let character=try? JSONValue.object(native).decode(OwnedCharacter.self){library.applyCloudCreation(character,id:id)}
    }
    private func refreshReferencedCatalog()async throws {
        guard Date().timeIntervalSince(catalogRefreshedAt)>30 else{return}
        // Cache a bounded first marketplace page; individually resolve every
        // subscribed character so subscriptions beyond this page remain usable.
        let page=try await call("GET","/v1/characters?limit=100")
        if case .array(let items)=page.object?["items"] {
            applying=true
            for item in items where item.object?["owned"]?.bool != true {
                if let id=item.object?["id"]?.string{applyCharacter(item,id:id,author:item.object?["author_id"]?.string,owned:false)}
            }
            applying=false
        }
        for id in library.archive.accounts[owner]?.subscriptions ?? [] where library.model(id)==nil {
            do {
                let item=try await call("GET","/v1/characters/"+id)
                applying=true;applyCharacter(item,id:id,author:item.object?["author_id"]?.string,owned:item.object?["owned"]?.bool == true);applying=false
            }catch PlatformError.status(404){continue}
        }
        let authors=Set(library.followedAuthors+library.archive.creations.compactMap(\.authorID))
        for id in authors where id != library.currentAuthor?.id && id != AuthorProfile.starry.id {
            do {
                let item=try await call("GET","/v1/authors/"+id),b=item.object?["data"]?.object ?? [:]
                applying=true
                library.applyCloudPublicAuthor(AuthorProfile(id:id,name:b["name"]?.string ?? "星夜创作者",bio:b["bio"]?.string ?? "",avatar:b["avatar"]?.string ?? "moon",revision:int(item,"version")))
                applying=false
            }catch PlatformError.status(404){continue}
        }
        catalogRefreshedAt=Date()
    }
    private func key(_ kind:String,_ id:String)->String{kind+":"+id}
    private func split(_ value:String)->(String,String){let pair=value.split(separator:":",maxSplits:1).map(String.init);return(pair[0],pair[1])}
    private func int(_ value:JSONValue,_ field:String)->Int{Int(value.object?[field]?.number ?? 0)}
    private func removable(_ value:String)->Bool{["subscription","follow","memory","moment","character"].contains(split(value).0)}
    private func rank(_ value:String)->Int{["author","character","settings","subscription","follow","preference","conversation","message","memory","moment"].firstIndex(of:split(value).0) ?? 99}
    private func snapshot()throws->[String:JSONValue]{
        var result:[String:JSONValue]=[:]
        result[key("settings","settings")] = .object(["theme":.string(ThemeSettings.shared.paletteID),"style":.string(ThemeSettings.shared.style),
            "chat_font_size":.number(store.chatDisplay.fontSize),"last_character":.string(library.lastCharacter ?? ""),
            "default_nickname":.string(store.defaultNickname)])
        if let author=library.currentAuthor{result[key("author",author.id)] = .object(["name":.string(author.name),"bio":.string(author.bio),"avatar":.string(author.avatar)])}
        for id in library.archive.accounts[owner]?.subscriptions ?? []{result[key("subscription",id)] = .object(["id":.string(id)])}
        for id in library.followedAuthors{result[key("follow",id)] = .object(["id":.string(id)])}
        for creation in library.creations{
            var native=try JSONValue.encode(creation).object ?? [:]
            native.removeValue(forKey:"ownerID");native.removeValue(forKey:"authorID")
            result[key("character",creation.id)] = .object(["name":.string(creation.profile.name),"description":.string(creation.profile.background),
                "visibility":.string(creation.published ? "public":"private"),"base_id":.string(creation.baseID),"data":.object(["native":.object(native)])])
        }
        for (id,record) in store.currentRecords {
            var preferences:[String:JSONValue]=["profile":try .encode(record.profile),"view_pose":try .encode(record.lastViewPose),"greeting":.null,"experiences":.null]
            if let value=record.greeting{preferences["greeting"]=try .encode(value)}
            if var experience=record.experiences{experience.moments=[];preferences["experiences"]=try .encode(experience)}
            result[key("preference",id)] = .object(preferences)
            if !record.messages.isEmpty || library.archive.accounts[owner]?.hiddenConversations[id] != nil {
                result[key("conversation",id)] = .object(["hidden":.bool(library.isConversationHidden(id,latestMessage:record.messages.last?.date)),"pinned":.bool(false)])
            }
            for message in record.messages{
                result[key("message",id+"/"+message.id.uuidString.lowercased())] = .object(["role":.string(message.role),"text":.string(message.text),
                    "created_at":.string(ISO8601DateFormatter().string(from:message.date)),"data":.object(["native":try .encode(message)])])
            }
            for memory in record.memories{result[key("memory",id+"/"+memory.id.uuidString.lowercased())]=try .encode(memory)}
            for moment in record.together.moments{result[key("moment",id+"/"+moment.id.uuidString.lowercased())]=try .encode(moment)}
        }
        for (key,value) in result { if let old=state.shadows[key]?.body { result[key]=AccountSyncMerge.overlay(known:value,on:old) } }
        return result
    }
    private func normalize(_ change:JSONValue)->Remote?{
        guard let c=change.object,let kind=c["kind"]?.string,let id=c["resource_id"]?.string,let data=c["data"] else{return nil}
        var body=data;let version=int(data,"version")
        switch kind {
        case "conversation_clear","conversation_reset":break
        case "account":body=data.object?["profile"] ?? .object([:])
        case "profile","settings","preference","author","memory","moment":body=data.object?["data"] ?? .object([:])
        case "conversation":body = .object(["hidden":data.object?["hidden"] ?? .bool(false),"pinned":data.object?["pinned"] ?? .bool(false)])
        case "message":body = .object(["role":data.object?["role"] ?? .string("assistant"),"text":data.object?["text"] ?? .string(""),
            "created_at":data.object?["created_at"] ?? .string(""),"data":data.object?["data"] ?? .object([:])])
        case "character":body = .object(Dictionary(uniqueKeysWithValues:["name","description","visibility","base_id","data"].map{($0,data.object?[$0] ?? .null)}))
        case "subscription","follow":break
        default:return nil
        }
        if kind=="preference",var value=body.object {
            // Merge Patch removes null keys. Normalize optional known fields
            // so a server acknowledgement does not create an endless outbox.
            if value["greeting"]==nil { value["greeting"] = .null }
            if value["experiences"]==nil { value["experiences"] = .null }
            body = .object(value)
        }
        return Remote(kind:kind == "profile" ? "account":kind,id:id,version:version,body:body,deleted:c["deleted"]?.bool == true)
    }
    private func receive(_ remote:Remote,pending:[String:JSONValue])throws{
        let k=key(remote.kind,remote.id),new=remote.deleted ? JSONValue.null:remote.body
        let role=remote.id.split(separator:"/",maxSplits:1).first.map(String.init) ?? remote.id
        if store.record(role).pendingDeletionID != nil,
           ["message","memory","moment","preference","conversation_clear","conversation_reset"].contains(remote.kind) {return}
        if remote.kind=="conversation_reset",let reset=remote.body.object?["reset_id"]?.string {
            guard remote.version >= (store.record(remote.id).conversationResetVersion ?? 0) else {return}
            applying=true;defer{applying=false}
            if store.record(remote.id).conversationResetID != reset {
                onConversationReset?(remote.id)
                SpeechClipCache.shared.removeConversation(scope:owner+"|"+remote.id,messages:store.record(remote.id).messages)
                store.update(remote.id){$0.resetConversation(reset,version:remote.version)}
            } else if remote.version > (store.record(remote.id).conversationResetVersion ?? 0) {
                store.update(remote.id){$0.conversationResetVersion=remote.version}
            }
            let prefixes=["message:","memory:","moment:"].map{$0+remote.id+"/"}
            state.shadows=state.shadows.filter{!prefixes.contains(where:$0.key.hasPrefix)}
            state.conflicts=state.conflicts.filter{!prefixes.contains(where:$0.key.hasPrefix) && $0.key != "preference:"+remote.id}
            if store.error != nil {throw CocoaError(.fileWriteUnknown)}
            return
        }
        if remote.kind=="conversation_clear" {
            applying=true;defer{applying=false}
            let prefix="message:"+remote.id+"/"
            store.update(remote.id){record in
                record.messages.removeAll{pending[prefix+$0.id.uuidString.lowercased()]==nil}
            }
            state.shadows=state.shadows.filter{!$0.key.hasPrefix(prefix)}
            state.conflicts=state.conflicts.filter{!$0.key.hasPrefix(prefix)}
            if store.error != nil {throw CocoaError(.fileWriteUnknown)}
            return
        }
        switch AccountSyncMerge.decide(knownVersion:state.shadows[k]?.version,known:state.shadows[k]?.body,pending:pending[k],remoteVersion:remote.version,remote:new) {
        case .stale:return
        case .conflict:state.conflicts[k]=remote;return
        case .keepLocal:
            // A newly created resource or an unchanged server acknowledgement
            // provides the CAS baseline without erasing the unsent local edit.
            if remote.deleted{state.shadows.removeValue(forKey:k)}else{state.shadows[k]=Shadow(version:remote.version,body:remote.body)}
            return
        case .apply:break
        }
        applying=true;defer{applying=false}
        try apply(remote)
        if store.error != nil || library.error != nil {throw CocoaError(.fileWriteUnknown)}
        if remote.deleted{state.shadows.removeValue(forKey:k)}else{state.shadows[k]=Shadow(version:remote.version,body:remote.body)}
        state.conflicts.removeValue(forKey:k)
    }
    private func apply(_ remote:Remote)throws{
        let b=remote.body.object ?? [:]
        switch remote.kind{
        case "account":account.updateCloudProfile(version:remote.version,profile:b)
        case "settings":
            if let v=b["theme"]?.string{ThemeSettings.shared.paletteID=v};if let v=b["style"]?.string{ThemeSettings.shared.style=v}
            if let v=b["chat_font_size"]?.number{store.chatDisplay.fontSize=v;_ = store.saveChatDisplay()}
            if let v=b["default_nickname"]?.string {store.saveDefaultNickname(v)}
            library.applyCloudLastCharacter(b["last_character"]?.string)
        case "subscription":
            let ids=library.archive.accounts[owner]?.subscriptions ?? []
            library.applyCloudRelations(subscriptions:remote.deleted ? ids.filter{$0 != remote.id}:Array(Set(ids+[remote.id])).sorted(),follows:library.followedAuthors)
        case "follow":
            // Followed creators may not have been visited locally; their public
            // profile is fetched separately from the account-scoped relation.
            library.applyCloudRelations(subscriptions:library.archive.accounts[owner]?.subscriptions ?? [],follows:remote.deleted ? library.followedAuthors.filter{$0 != remote.id}:Array(Set(library.followedAuthors+[remote.id])).sorted())
        case "author":library.applyCloudAuthor(AuthorProfile(id:remote.id,name:b["name"]?.string ?? "星夜伙伴",bio:b["bio"]?.string ?? "",avatar:b["avatar"]?.string ?? "moon",revision:remote.version))
        case "character":
            if remote.deleted{library.applyCloudCreation(nil,id:remote.id)}
            else { applyCharacter(remote.body,id:remote.id,author:library.currentAuthor?.id,owned:true) }
        case "preference":
            store.update(remote.id){record in
                if let p=b["profile"],let profile=try? p.decode(CharacterProfile.self){record.profile=profile}
                if let v=b["view_pose"]{record.viewPose=try? v.decode(CharacterViewPose.self)}
                if let v=b["greeting"]{record.greeting=try? v.decode(ConversationGreetingHistory.self)}
                if let v=b["experiences"],var experience=try? v.decode(CompanionExperiences.self){experience.moments=record.together.moments;record.experiences=experience}
            }
        case "conversation":library.applyCloudConversation(remote.id,hidden:b["hidden"]?.bool == true)
        case "message","memory","moment":
            let path=remote.id.split(separator:"/",maxSplits:1).map(String.init);guard path.count==2,let uuid=UUID(uuidString:path[1]) else{return}
            store.update(path[0]){record in
                if remote.kind=="message",let native=b["data"]?.object?["native"],let message=try? native.decode(CompanionMessage.self){
                    record.messages.removeAll{$0.id==uuid};record.messages.append(message);record.messages.sort{$0.date<$1.date}
                }else if remote.kind=="memory"{
                    record.memories.removeAll{$0.id==uuid};if !remote.deleted,let value=try? remote.body.decode(CompanionMemory.self){record.memories.append(value)}
                }else if remote.kind=="moment"{
                    var experience=record.together;experience.moments.removeAll{$0.id==uuid}
                    if !remote.deleted,let value=try? remote.body.decode(TogetherMoment.self){experience.moments.append(value)};record.experiences=experience
                }
            }
        default:break
        }
    }
    private func push(_ k:String,body:JSONValue,version:Int)async throws->JSONValue{
        let (kind,id)=split(k);var value=body.object ?? [:];let expected=JSONValue.number(Double(version))
        let role=id.split(separator:"/",maxSplits:1).first.map(String.init) ?? id
        if ["message","memory","moment","preference","conversation"].contains(kind),store.record(role).pendingDeletionID != nil {throw CancellationError()}
        switch kind{
        case "subscription","follow":return try await call(body == .null ? "DELETE":"PUT","/v1/me/"+(kind=="subscription" ? "subscriptions/":"follows/")+id)
        case "settings","author","preference":
            let path=kind=="preference" ? "/v1/characters/\(id)/preferences" : "/v1/me/"+(kind=="author" ? "author":"settings")
            // RFC 7396 only sends changed fields. Unknown future fields survive.
            let patch=AccountSyncMerge.diff(old:state.shadows[k]?.body ?? .object([:]),new:body)
            var mutation:[String:JSONValue]=["expected_version":expected,"patch":patch]
            if kind=="preference" {mutation["conversation_reset"] = .string(store.record(id).conversationResetID ?? "")}
            return try await call("PATCH",path,.object(mutation))
        case "character":
            if body == .null{return try await call("DELETE","/v1/characters/\(id)?version=\(version)")}
            if version==0{value["id"] = .string(id);return try await call("POST","/v1/characters",.object(value))}
            value.removeValue(forKey:"base_id");value["expected_version"]=expected;return try await call("PUT","/v1/characters/"+id,.object(value))
        case "conversation":value["expected_version"]=expected;return try await call("PUT","/v1/conversations/"+id,.object(value))
        default:
            let parts=id.split(separator:"/",maxSplits:1).map(String.init)
            let suffix=kind=="message" ? "messages":kind=="memory" ? "memories":"moments"
            let path="/v1/conversations/\(parts[0])/\(suffix)/\(parts[1])"
            if body == .null{return try await call("DELETE",path+"?version=\(version)")}
            if kind != "message"{value=["data":body]};value["expected_version"]=expected
            value["conversation_reset"] = .string(store.record(parts[0]).conversationResetID ?? "")
            return try await call("PUT",path,.object(value))
        }
    }
    private func resolveConflicts(){
        // Preserve all conflicting local values before the user chooses cloud.
        do {
            try ensure(owner)
            let local=try snapshot();let backup=directory.appendingPathComponent(owner+"-conflict-\(Int(Date().timeIntervalSince1970)).json")
            try JSONEncoder().encode(local.filter{state.conflicts[$0.key] != nil}).write(to:backup,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            for remote in Array(state.conflicts.values){try receive(remote,pending:[:])}
            state.conflicts=[:];account.hasSyncConflicts=false;try save();schedule(immediate:true)
        }catch{account.syncStatus="冲突副本尚未保存，请重试"}
    }
}
