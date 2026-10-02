import Foundation

enum MarketShelf: String, CaseIterable, Identifiable {
    case recommended = "精选", all = "全部", creators = "用户作品"
    var id: String { rawValue }
}
enum MarketSort: String, CaseIterable, Identifiable {
    case recommended = "推荐排序", updated = "最近更新", name = "角色名称"
    var id: String { rawValue }
}
struct MarketQuery: Equatable {
    var text = ""
    var shelf = MarketShelf.all
    var category = "全部"
    var sort = MarketSort.recommended
    var subscribedOnly = false
    var followedAuthorsOnly = false
    var hasFilters: Bool { category != "全部" || subscribedOnly || followedAuthorsOnly }
}

/// A discovery listing is public metadata, independent of chat history and
/// personal display settings. A future network catalog can supply these entries
/// without changing the shelf/search/card presentation.
struct CharacterMarketItem: Identifiable {
    let model: ModelDescriptor
    let profile: CharacterProfile
    let author: AuthorProfile?
    let categories: [String]
    let featured: Bool
    let rank: Int
    let updatedAt: Date
    let isCreatorWork: Bool
    var id: String { model.id }
    var authorName: String { author?.name ?? "作者暂不可用" }
    var sourceLabel: String { isCreatorWork ? "创作者作品" : "星夜精选" }
}

@MainActor enum CharacterMarketplace {
    private struct Curation: Decodable {
        struct Entry: Decodable { let categories:[String]; let featured:Bool; let rank:Int }
        let schemaVersion: Int
        let characters: [String:Entry]
    }
    private static let curation: [String:Curation.Entry] = {
        guard let url = Bundle.main.url(forResource:"MarketplaceCatalog",withExtension:"json"),
              let data = try? Data(contentsOf:url), let catalog = try? JSONDecoder().decode(Curation.self,from:data),
              catalog.schemaVersion == 1 else { return [:] }
        return catalog.characters
    }()
    static func localCatalog(_ library:CharacterLibrary) -> [CharacterMarketItem] {
        library.discover.compactMap { model in
            let creation = library.creation(model.id)
            // Owned private drafts belong in My creations, never the marketplace.
            guard creation == nil || creation?.published == true else { return nil }
            let metadata = creation == nil ? curation[model.id] : nil
            let persona=creation == nil ? CharacterPublicProfile.find(model.id) : nil
            let routes=persona?.scenarios ?? []
            let categories=(metadata?.categories ?? ["日常"])+(persona?.englishOnly == true ? ["英语"] : routes.contains(where:{$0.category.contains("恋爱") || $0.category.contains("约会")}) ? ["恋爱"] : routes.isEmpty ? [] : ["剧情"])
            return CharacterMarketItem(model:model,profile:model.conversationProfile(preserving:nil),
                author:library.author(for:model.id),categories:Array(Set(categories)).sorted(),
                featured:metadata?.featured ?? false,rank:metadata?.rank ?? 1000,
                updatedAt:library.updatedAt(model.id),isCreatorWork:creation != nil)
        }
    }
    static func categories(_ items:[CharacterMarketItem]) -> [String] {
        let available = Set(items.flatMap(\.categories))
        let preferred = ["恋爱","英语","剧情","日常","治愈","元气","校园","幻想"]
        return ["全部"] + preferred.filter(available.contains) + available.subtracting(preferred).sorted()
    }
    static func results(_ items:[CharacterMarketItem],query:MarketQuery,
                        subscriptions:Set<String>,followedAuthors:Set<String>) -> [CharacterMarketItem] {
        items.filter { item in
            (query.shelf != .creators || item.isCreatorWork) &&
            (query.category == "全部" || item.categories.contains(query.category)) &&
            (!query.subscribedOnly || subscriptions.contains(item.id)) &&
            (!query.followedAuthorsOnly || item.author.map { followedAuthors.contains($0.id) } == true) &&
            CharacterSearch.matches(query.text,model:item.model,profile:item.profile,
                authorName:([item.authorName]+item.categories+[CharacterPublicProfile.find(item.model.runtimeID)?.occupation ?? ""]+(CharacterPublicProfile.find(item.model.runtimeID)?.scenarios?.map(\.title) ?? [])).joined(separator:" "))
        }.sorted { a,b in
            if query.sort == .name {
                let order = a.profile.name.localizedStandardCompare(b.profile.name)
                if order != .orderedSame { return order == .orderedAscending }
            } else if query.sort == .updated, a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            else if query.sort == .recommended, a.rank != b.rank { return a.rank < b.rank }
            return a.id < b.id
        }
    }
}
