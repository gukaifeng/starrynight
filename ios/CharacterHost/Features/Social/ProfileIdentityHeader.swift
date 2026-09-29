import SwiftUI

/// The same identity geometry for a character and the person who created it.
struct ProfileIdentityHeader<Avatar:View,Accessory:View>:View {
    static var avatarSize:CGFloat { 52 }
    let name:String
    let subtitle:String
    let nameID:String
    @ViewBuilder let avatar:() -> Avatar
    @ViewBuilder let accessory:() -> Accessory
    var body:some View {
        HStack(spacing:12) {
            avatar().frame(width:52,height:52)
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:10) {
                    Text(name).font(.system(size:20,weight:.semibold,design:.rounded))
                        .lineLimit(1).minimumScaleFactor(0.8).accessibilityIdentifier(nameID)
                    accessory()
                    Spacer(minLength:0)
                }
                Text(subtitle).font(.system(size:11)).foregroundStyle(Theme.accent).lineLimit(1)
            }
        }
    }
}

struct ProfileRelationshipLabel:View {
    let title:String
    var selected:Bool = false
    var body:some View {
        Text(title).font(.system(size:11,weight:.medium))
            .fixedSize().padding(.horizontal,12).frame(height:28)
            .background(Theme.accent.opacity(selected ? 0.06 : 0.13),in:Capsule())
            .frame(minWidth:44,minHeight:44).contentShape(Rectangle())
    }
}
