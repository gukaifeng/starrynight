import AppKit

// One authored geometry generates editable SVG, resolution-independent PDF and
// iOS's required opaque raster app icon. No raster trace or external dependency.
let root = URL(fileURLWithPath:CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let brand = root.appendingPathComponent("assets/brand")
let assets = root.appendingPathComponent("ios/StarryNight/Resources/Assets.xcassets")
let moon = CGMutablePath()
moon.move(to:CGPoint(x:615,y:222))
moon.addCurve(to:CGPoint(x:484,y:205),control1:CGPoint(x:568,y:205),control2:CGPoint(x:526,y:199))
moon.addCurve(to:CGPoint(x:225,y:570),control1:CGPoint(x:304,y:227),control2:CGPoint(x:200,y:393))
moon.addCurve(to:CGPoint(x:591,y:842),control1:CGPoint(x:250,y:747),control2:CGPoint(x:414,y:867))
moon.addCurve(to:CGPoint(x:809,y:687),control1:CGPoint(x:688,y:828),control2:CGPoint(x:770,y:768))
moon.addCurve(to:CGPoint(x:516,y:667),control1:CGPoint(x:716,y:738),control2:CGPoint(x:600,y:731))
moon.addCurve(to:CGPoint(x:472,y:283),control1:CGPoint(x:381,y:564),control2:CGPoint(x:363,y:378))
moon.addCurve(to:CGPoint(x:615,y:222),control1:CGPoint(x:514,y:251),control2:CGPoint(x:562,y:231))
moon.closeSubpath()
let star = CGMutablePath()
star.move(to:CGPoint(x:705,y:248))
star.addCurve(to:CGPoint(x:800,y:343),control1:CGPoint(x:713,y:313),control2:CGPoint(x:735,y:335))
star.addCurve(to:CGPoint(x:705,y:438),control1:CGPoint(x:735,y:351),control2:CGPoint(x:713,y:373))
star.addCurve(to:CGPoint(x:610,y:343),control1:CGPoint(x:697,y:373),control2:CGPoint(x:675,y:351))
star.addCurve(to:CGPoint(x:705,y:248),control1:CGPoint(x:675,y:335),control2:CGPoint(x:697,y:313))
star.closeSubpath()
let paths:[CGPath] = [moon,star]
let night = "#101114", white = "#F1F2EE"
func color(_ hex:String)->CGColor {
    let value = UInt32(hex.dropFirst(),radix:16)!
    return CGColor(red:CGFloat((value>>16)&255)/255,green:CGFloat((value>>8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)
}
func svgPath(_ path:CGPath)->String {
    var commands:[String] = []
    func point(_ p:CGPoint)->String { "\(Int(p.x)) \(Int(p.y))" }
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint: commands.append("M " + point(e.points[0]))
        case .addLineToPoint: commands.append("L " + point(e.points[0]))
        case .addCurveToPoint: commands.append("C " + (0..<3).map { point(e.points[$0]) }.joined(separator:" "))
        case .closeSubpath: commands.append("Z")
        default: fatalError("Unsupported geometry")
        }
    }
    return commands.joined(separator:" ")
}
func svg(fill:String,background:Bool)->String {
    let bg = background ? "<rect width=\"1024\" height=\"1024\" fill=\"\(night)\"/>\n" : ""
    let geometry = paths.map { "<path d=\"\(svgPath($0))\" fill=\"\(fill)\"/>" }.joined(separator:"\n")
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
    <title id="title">星夜</title>
    <desc id="desc">弯月为一颗四芒星留出空间。单色矢量标志。</desc>
    \(bg)\(geometry)
    </svg>

    """
}
func paint(_ context:CGContext,edge:CGFloat,opaque:Bool = true) {
    if opaque { context.setFillColor(color(night)); context.fill(CGRect(x:0,y:0,width:edge,height:edge)) }
    context.saveGState();context.translateBy(x:0,y:edge);context.scaleBy(x:edge/1024,y:-edge/1024)
    context.setFillColor(color(white));paths.forEach { context.addPath($0);context.fillPath() }
    context.restoreGState()
}
try FileManager.default.createDirectory(at:brand,withIntermediateDirectories:true)
try svg(fill:night,background:false).write(to:brand.appendingPathComponent("starry-mark.svg"),atomically:true,encoding:.utf8)
try svg(fill:white,background:false).write(to:brand.appendingPathComponent("starry-mark-light.svg"),atomically:true,encoding:.utf8)
try svg(fill:white,background:true).write(to:brand.appendingPathComponent("starry-app-icon.svg"),atomically:true,encoding:.utf8)
for (size,destination) in [(1024,assets.appendingPathComponent("AppIcon.appiconset/AppIcon.png")),(1024,brand.appendingPathComponent("starry-minimal-preview.png"))] {
    let ctx = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    paint(ctx,edge:CGFloat(size))
    let bitmap = NSBitmapImageRep(cgImage:ctx.makeImage()!)
    try bitmap.representation(using:.png,properties:[:])!.write(to:destination)
}
let pdfURL = assets.appendingPathComponent("BrandMark.imageset/BrandMark.pdf")
var box = CGRect(x:0,y:0,width:1024,height:1024)
let pdf = CGContext(pdfURL as CFURL,mediaBox:&box,nil)!
pdf.beginPDFPage(nil);paint(pdf,edge:1024,opaque:false);pdf.endPDFPage();pdf.closePDF()
let contents = """
{"images":[{"filename":"BrandMark.pdf","idiom":"universal"}],"info":{"author":"xcode","version":1},"properties":{"preserves-vector-representation":true}}

"""
try contents.write(to:assets.appendingPathComponent("BrandMark.imageset/Contents.json"),atomically:true,encoding:.utf8)
print("Generated Starry SVG originals, vector PDF BrandMark and opaque 1024px iOS icon.")
