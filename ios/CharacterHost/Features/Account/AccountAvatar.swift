import SwiftUI
import ImageIO
import CryptoKit

/// Original vector artwork. No generated image/provider call is required.
struct StarryDefaultAvatar:View {
    var kind="starry-cat-v1"
    var body:some View {
        GeometryReader {geo in
            let s=geo.size.width
            ZStack {
                LinearGradient(colors:[Color(hex:0x111A31),Color(hex:0x24475C),Color(hex:0x86748F)],startPoint:.topLeading,endPoint:.bottomTrailing)
                Circle().fill(Color.white.opacity(0.07)).frame(width:s*0.88,height:s*0.88).offset(x:s*0.17,y:s*0.14)
                Image(systemName:"sparkle").font(.system(size:s*0.15,weight:.light)).foregroundStyle(Color(hex:0xE8DDC7)).offset(x:s*0.28,y:-s*0.26)
                if kind=="starry-orbit-v1" {
                    Image(systemName:"moon.fill").font(.system(size:s*0.50)).foregroundStyle(Color(hex:0xDDE5F0))
                    Ellipse().stroke(Color(hex:0xDBBCA3).opacity(0.8),lineWidth:s*0.018).frame(width:s*0.76,height:s*0.23).rotationEffect(.degrees(-25))
                } else {
                    let bunny=kind=="starry-bunny-v1"
                    ForEach([-1.0,1.0],id:\.self) {side in
                        if bunny {Capsule().fill(Color(hex:0xD4DBE6)).frame(width:s*0.16,height:s*0.41).rotationEffect(.degrees(side*12)).offset(x:s*side*0.16,y:-s*0.20)}
                        else {StarryCatEar().fill(Color(hex:0xD4DBE6)).frame(width:s*0.26,height:s*0.30).rotationEffect(.degrees(side*8)).offset(x:s*side*0.19,y:-s*0.15)}
                    }
                    Ellipse().fill(LinearGradient(colors:[Color(hex:0xE8EDF6),Color(hex:0xB2C6DA)],startPoint:.top,endPoint:.bottom)).frame(width:s*0.66,height:s*0.53).offset(y:s*0.12)
                    ForEach([-1.0,1.0],id:\.self) {side in
                        Capsule().fill(Color(hex:0x243A54)).frame(width:s*0.035,height:s*0.085).rotationEffect(.degrees(side*10)).offset(x:s*side*0.13,y:s*0.10)
                        Ellipse().fill(Color(hex:0xDBA8B3).opacity(0.55)).frame(width:s*0.10,height:s*0.05).offset(x:s*side*0.20,y:s*0.17)
                    }
                    StarrySmile().stroke(Color(hex:0x354A62),style:StrokeStyle(lineWidth:s*0.018,lineCap:.round)).frame(width:s*0.10,height:s*0.05).offset(y:s*0.19)
                }
            }.frame(width:s,height:s)
        }
    }
}
private struct StarryCatEar:Shape {
    func path(in r:CGRect)->Path {Path {p in p.move(to:CGPoint(x:r.width*0.06,y:r.height));p.addQuadCurve(to:CGPoint(x:r.width*0.32,y:r.height*0.06),control:CGPoint(x:r.width*0.05,y:r.height*0.05));p.addQuadCurve(to:CGPoint(x:r.width,y:r.height),control:CGPoint(x:r.width*0.8,y:r.height*0.28));p.closeSubpath()}}
}
private struct StarrySmile:Shape {
    func path(in r:CGRect)->Path {Path {p in p.move(to:.zero);p.addQuadCurve(to:CGPoint(x:r.width,y:0),control:CGPoint(x:r.width/2,y:r.height*1.5))}}
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
