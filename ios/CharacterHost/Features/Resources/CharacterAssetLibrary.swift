import Foundation
import Observation
import AVFoundation

struct CharacterStoreListing:Codable,Sendable,Identifiable {
    struct Media:Codable,Sendable {var url:String?;let size:Int64;let sha256,contentType:String}
    let id,name,description,delivery:String
    let downloadBytes,releaseVersion:Int64
    var media:[String:Media]
    let data:[String:JSONValue]
}
@MainActor @Observable final class CharacterAssetLibrary {
    static let shared=CharacterAssetLibrary()
    enum Phase:Equatable {case missing,downloading(Double,String),ready,failed(String)}
    private(set) var listings:[CharacterStoreListing]=[]
    private(set) var states:[String:Phase]=[:]
    private(set) var error:String?
    private(set) var refreshing=false
    private(set) var auditionID:String?
    @ObservationIgnored private var auditionEnd:Task<Void,Never>?
    @ObservationIgnored private var player:AVAudioPlayer?
    @ObservationIgnored private var tasks:[String:Task<URL,Error>]=[:]
    @ObservationIgnored private var releases:[String:URL]=[:]
    @ObservationIgnored private var versions:[String:Int64]=[:]
    @ObservationIgnored private var owner=""
    private static let cache=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("character-store.json")
    init() {
        if let data=try? Data(contentsOf:Self.cache),let values=try? JSONDecoder().decode([CharacterStoreListing].self,from:data) {listings=values;Self.registerModels(values)}
    }
    private static func registerModels(_ listings:[CharacterStoreListing]) {
        CharacterDeliveryPolicy.setStoreIDs(Set(listings.filter {$0.delivery=="oss"}.map(\.id)))
        var models:[ModelDescriptor]=[]
        for listing in listings {
            if var model=try? listing.data["descriptor"]?.decode(ModelDescriptor.self),model.id==listing.id,
               let collection=try? listing.data["collection"]?.decode(CharacterCollection.self),collection.modelID==model.id {
                model.collectionSnapshot=collection;models.append(model)
            }
        }
        ModelDescriptor.installStoreModels(models)
        CharacterPublicProfile.installStoreProfiles(listings.compactMap {try? $0.data["public_profile"]?.decode(CharacterPublicProfile.self)})
    }
    static var platform:String {
#if targetEnvironment(simulator)
        "ios-simulator"
#else
        "ios"
#endif
    }
    private struct Policy:Decodable {let downloadOnly:[String]}
    private static let remoteIDs:Set<String> = {
        guard let url=Bundle.main.url(forResource:"CharacterDelivery",withExtension:"json"),
              let value=try? JSONDecoder().decode(Policy.self,from:Data(contentsOf:url)) else {return []}
        return Set(value.downloadOnly)
    }()
    func activate(_ accountID:String) {
        guard owner != accountID else {return}
        tasks.values.forEach {$0.cancel()};tasks.removeAll();states.removeAll();releases.removeAll();versions.removeAll()
        CharacterInstalledResources.clear();owner=accountID;stopAudition()
        Task {for id in Self.remoteIDs{_ = try? await restore(id,accountID:accountID)}}
    }
    func listing(_ id:String)->CharacterStoreListing? {listings.first {$0.id==id}}
    func requiresDownload(_ id:String)->Bool {listing(id)?.delivery=="oss" || Self.remoteIDs.contains(id)}
    func phase(_ id:String)->Phase {
        if states[id] == .ready,needsInstallation(id){return .missing}
        return requiresDownload(id) ? states[id] ?? .missing : .ready
    }
    func needsInstallation(_ id:String)->Bool {requiresDownload(id) && (releases[id]==nil || (versions[id] ?? 0)<(listing(id)?.releaseVersion ?? 0))}
    func localRelease(_ id:String)->URL? {releases[id]}
    func restore(_ id:String,accountID:String) async throws->URL? {
        guard owner==accountID else {throw CancellationError()}
        if let release=releases[id]{return release}
        guard let release=try await CharacterDownloadStore.shared.installed(characterID:id,accountID:accountID,platform:Self.platform) else {return nil}
        guard owner==accountID else {throw CancellationError()}
        releases[id]=release;states[id] = .ready;CharacterInstalledResources.register(id,release:release)
        if let data=try? Data(contentsOf:release.appendingPathComponent("content/package.json")),let package=try? JSONDecoder().decode(CharacterDownloadStore.Package.self,from:data){versions[id]=package.version}
        return release
    }
    func refresh() async {
        guard !refreshing else {return};refreshing=true;defer {refreshing=false}
        do {
            struct Page:Decodable {let items:[CharacterStoreListing];let next:String?}
            var result:[CharacterStoreListing]=[],after=""
            repeat {
                let value=try await PlatformAPI.shared.request("GET","/v1/store/characters?limit=200&platform="+Self.platform+"&after="+after)
                let decoder=JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
                let page=try decoder.decode(Page.self,from:JSONEncoder().encode(value))
                result+=page.items;let next=page.next ?? ""
                guard next.isEmpty || next>after,result.count<=10000 else {throw PlatformError.invalidResponse};after=next
            }while !after.isEmpty
            Self.registerModels(result)
            listings=result;error=nil
            var durable=result
            for i in durable.indices {for key in Array(durable[i].media.keys){durable[i].media[key]?.url=nil}}
            try JSONEncoder().encode(durable).write(to:Self.cache,options:.atomic)
        } catch {self.error="商店暂时无法刷新，已下载的角色仍可使用。"}
    }
    func download(_ id:String,accountID:String) async throws->URL {
        if let ready=try await restore(id,accountID:accountID),!needsInstallation(id){return ready}
        if let task=tasks[id]{return try await task.value}
        guard PlatformAPI.shared.activeSession?.user.id==accountID else {throw PlatformError.status(401)}
        states[id] = .downloading(0,"正在准备下载")
        let library=self
        let task=Task { @MainActor in
            // A new ticket is requested for each attempt; expired links never persist.
            try await PlatformAPI.shared.downloadCharacter(id,progress:{progress,label in
                Task { @MainActor [weak library] in guard let library,library.owner==accountID,library.tasks[id] != nil else{return};library.states[id] = .downloading(progress,label) }
            })
        };tasks[id]=task
        do {
            let release=try await task.value;guard owner==accountID else {throw CancellationError()}
            tasks[id]=nil;releases[id]=release;states[id] = .ready;CharacterInstalledResources.register(id,release:release)
            if let data=try? Data(contentsOf:release.appendingPathComponent("content/package.json")),let package=try? JSONDecoder().decode(CharacterDownloadStore.Package.self,from:data){versions[id]=package.version}
            return release
        } catch {
            tasks[id]=nil
            if owner==accountID{states[id] = error is CancellationError ? .missing : .failed(error.localizedDescription)}
            throw error
        }
    }
    func cancel(_ id:String){tasks[id]?.cancel()}
    func stopAudition(){auditionEnd?.cancel();auditionEnd=nil;player?.stop();player=nil;auditionID=nil}
    func audition(_ id:String) async {
        if auditionID==id{stopAudition();return};stopAudition();auditionID=id
        do {
            guard let raw=listing(id)?.media["audition"]?.url,let url=URL(string:raw),url.scheme=="https" else {throw PlatformError.invalidResponse}
            let (data,response)=try await URLSession.shared.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode==200,data.count<=4*1024*1024,auditionID==id else {throw PlatformError.invalidResponse}
            try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default,options:[.mixWithOthers]);try AVAudioSession.sharedInstance().setActive(true)
            player=try AVAudioPlayer(data:data);player?.play()
            let duration=player?.duration ?? 0
            auditionEnd=Task { @MainActor [weak self] in
                do{try await Task.sleep(for:.seconds(duration))}catch{return}
                if self?.auditionID==id{self?.stopAudition()}
            }
        } catch {if auditionID==id{stopAudition();self.error="试听暂时不可用，请刷新角色商店后再试。"}}
    }
}
