import SwiftUI

/// Authored artwork is bound to a runtime character, never to a viewer's saved room or personality.
/// A locally created character inherits its base model's cover until its author supplies a cover.
struct CharacterCoverDefinition: Decodable {
    let runtimeID: String
    let asset: String
    let environmentID: String
    let focusX: CGFloat
    let focusY: CGFloat
    let headBounds:CharacterHeadBounds?

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
                if let head=definition?.headBounds {
                    CharacterFocusedArtwork(artwork:artwork,head:head,banner:focalCrop)
                } else {
                let scale = max(geometry.size.width/artwork.size.width,geometry.size.height/artwork.size.height)
                let width = artwork.size.width*scale, height = artwork.size.height*scale
                let focalX = focalCrop ? definition?.focusX ?? 0.5 : 0.5
                let focalY = focalCrop ? definition?.focusY ?? 0.3 : 0.5
                let x = min(0,max(geometry.size.width-width,geometry.size.width/2-width*focalX))
                let y = min(0,max(geometry.size.height-height,geometry.size.height/2-height*focalY))
                Image(uiImage:artwork).resizable().frame(width:width,height:height)
                    .offset(x:x,y:y)
                }
            } else { Theme.surface }
        }.clipped().accessibilityHidden(true)
    }
}

struct CharacterFocusedArtwork:View {
    let artwork:UIImage
    let head:CharacterHeadBounds
    var circle=false
    var banner=false
    var body:some View {
        GeometryReader { geometry in
            let frame=CharacterArtworkLayout.frame(source:artwork.size,target:geometry.size,head:head,circle:circle,banner:banner)
            ZStack(alignment:.topLeading) {
                if circle {
                Image(uiImage:artwork).resizable().scaledToFill()
                    .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                    .blur(radius:4)
                }
                Image(uiImage:artwork).resizable().frame(width:frame.width,height:frame.height)
                    .offset(x:frame.minX,y:frame.minY)
            // The foreground can be taller than the aperture. Centering this
            // outer frame would shift the reviewed head crop upward a second
            // time, cutting off ears/hats despite correct layout coordinates.
            }.frame(width:geometry.size.width,height:geometry.size.height,alignment:.topLeading).clipped()
        }.accessibilityHidden(true)
    }
}
