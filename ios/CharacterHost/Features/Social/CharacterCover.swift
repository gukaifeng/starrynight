import SwiftUI

/// Authored artwork is bound to a runtime character, never to a viewer's saved room or personality.
/// A locally created character inherits its base model's cover until its author supplies a cover.
struct CharacterCoverDefinition: Decodable {
    let runtimeID: String
    let asset: String
    let environmentID: String
    let focusX: CGFloat
    let focusY: CGFloat

    private struct Catalog: Decodable { let schemaVersion: Int; let covers: [CharacterCoverDefinition] }
    private static let catalog: [String: CharacterCoverDefinition] = {
        guard let url = Bundle.main.url(forResource:"CharacterCoverCatalog",withExtension:"json"),
              let data = try? Data(contentsOf:url), let catalog = try? JSONDecoder().decode(Catalog.self,from:data),
              catalog.schemaVersion == 1 else { return [:] }
        return Dictionary(catalog.covers.map { ($0.runtimeID,$0) },uniquingKeysWith:{ first,_ in first })
    }()
    static func find(_ model: ModelDescriptor) -> CharacterCoverDefinition? { catalog[model.runtimeID] }
}

struct CharacterCover: View {
    let model: ModelDescriptor
    /// Short profile banners keep the face at the authored focal point; discovery shows the full cover.
    var focalCrop = false
    private var definition: CharacterCoverDefinition? { CharacterCoverDefinition.find(model) }
    private var artwork: UIImage? { definition.flatMap { UIImage(named:$0.asset) } ?? UIImage(named:model.thumbnail) }

    var body: some View {
        GeometryReader { geometry in
            if let artwork, artwork.size.width > 0, artwork.size.height > 0 {
                let scale = max(geometry.size.width/artwork.size.width,geometry.size.height/artwork.size.height)
                let width = artwork.size.width*scale, height = artwork.size.height*scale
                let focalX = focalCrop ? definition?.focusX ?? 0.5 : 0.5
                let focalY = focalCrop ? definition?.focusY ?? 0.3 : 0.5
                let x = min(0,max(geometry.size.width-width,geometry.size.width/2-width*focalX))
                let y = min(0,max(geometry.size.height-height,geometry.size.height/2-height*focalY))
                Image(uiImage:artwork).resizable().frame(width:width,height:height)
                    .offset(x:x,y:y)
            } else { Theme.surface }
        }.clipped().accessibilityHidden(true)
    }
}
