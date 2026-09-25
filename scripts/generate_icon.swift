import AppKit

// Code-drawn vector mark, with no external artwork or font dependency.
let size = 1024
let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,
    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
NSColor(red:0.208,green:0.388,blue:0.914,alpha:1).setFill()
NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)).fill()
func face(_ points:[NSPoint], _ shade:CGFloat) {
    let path = NSBezierPath(); path.move(to:points[0])
    points.dropFirst().forEach { path.line(to:$0) }; path.close()
    NSColor(white:shade,alpha:1).setFill(); path.fill()
}
face([.init(x:512,y:813),.init(x:792,y:650),.init(x:512,y:488),.init(x:232,y:650)],1)
face([.init(x:232,y:615),.init(x:495,y:461),.init(x:495,y:166),.init(x:232,y:320)],0.86)
face([.init(x:529,y:461),.init(x:792,y:615),.init(x:792,y:320),.init(x:529,y:166)],0.96)
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage:context.makeImage()!)
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
