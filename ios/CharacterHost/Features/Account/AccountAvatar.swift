import SwiftUI
import ImageIO
import CryptoKit

/// Original vector artwork. No generated image/provider call is required.
struct StarryDefaultAvatar:View {
    var kind="starry-orbit-v1" // Legacy default references render the retained artwork.
    var body:some View {
        GeometryReader {geo in
            let s=geo.size.width
            ZStack {
                LinearGradient(colors:[Color(hex:0x111A31),Color(hex:0x24475C),Color(hex:0x86748F)],startPoint:.topLeading,endPoint:.bottomTrailing)
                Circle().fill(Color.white.opacity(0.07)).frame(width:s*0.88,height:s*0.88).offset(x:s*0.17,y:s*0.14)
                Image(systemName:"sparkle").font(.system(size:s*0.15,weight:.light)).foregroundStyle(Color(hex:0xE8DDC7)).offset(x:s*0.28,y:-s*0.26)
                Image(systemName:"moon.fill").font(.system(size:s*0.50)).foregroundStyle(Color(hex:0xDDE5F0))
                Ellipse().stroke(Color(hex:0xDBBCA3).opacity(0.8),lineWidth:s*0.018).frame(width:s*0.76,height:s*0.23).rotationEffect(.degrees(-25))
            }.frame(width:s,height:s)
        }
    }
}
enum AvatarImageProcessor {
    static func jpeg(_ data:Data) throws -> Data {
        guard data.count<=40*1024*1024,let source=CGImageSourceCreateWithData(data as CFData,nil),
              let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:512] as CFDictionary) else{throw PlatformError.invalidResponse}
        let image=UIImage(cgImage:thumbnail);let side=min(image.size.width,image.size.height)
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        let square=UIGraphicsImageRenderer(size:CGSize(width:256,height:256),format:format).image {context in
            UIColor(red:0.07,green:0.09,blue:0.14,alpha:1).setFill();context.fill(CGRect(x:0,y:0,width:256,height:256))
            let factor=256/side
            image.draw(in:CGRect(x:(256-image.size.width*factor)/2,y:(256-image.size.height*factor)/2,width:image.size.width*factor,height:image.size.height*factor))
        }
        guard let result=square.jpegData(compressionQuality:0.9),result.count<=512*1024 else{throw PlatformError.invalidResponse}
        return result
    }
}

actor AccountAvatarCache {
    static let shared=AccountAvatarCache()
    private var memory:[String:Data]=[:]
    func load(reference:String,session:PlatformSession) async throws -> Data {
        let hash=String(reference.dropFirst(7))
        guard hash.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else{throw PlatformError.invalidResponse}
        let key=session.user.id+"-"+hash
        if let data=memory[key]{return data}
        let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AccountAvatars",isDirectory:true).appendingPathComponent(session.user.id,isDirectory:true)
        let file=directory.appendingPathComponent(hash+".jpg")
        if let data=try? Data(contentsOf:file),valid(data,hash:hash){memory[key]=data;return data}
        let result=try await PlatformAPI.shared.request("GET","/v1/me/avatar",token:session.token)
        guard result.object?["sha256"]?.string==hash,let encoded=result.object?["image"]?.string,let data=Data(base64Encoded:encoded),valid(data,hash:hash) else{throw PlatformError.invalidResponse}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        memory[key]=data;return data
    }
    private func valid(_ data:Data,hash:String)->Bool {data.count<=128*1024 && SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()==hash}
}
