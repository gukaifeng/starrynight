import Foundation
import CoreGraphics

enum AdaptiveLayoutChecks {
    static func run() {
        var checks = 0
        func check(_ condition:Bool,_ message:String) { precondition(condition,message); checks += 1 }
        let windows:[(String,CGSize,AdaptiveViewerLayout.Insets)] = [
            ("phone portrait",CGSize(width:402,height:874),.init(top:62,bottom:34)),
            ("phone left",CGSize(width:874,height:402),.init(left:62,bottom:21,right:62)),
            ("phone right",CGSize(width:874,height:402),.init(left:62,bottom:21,right:62)),
            ("tablet portrait",CGSize(width:834,height:1210),.init(top:24,bottom:20)),
            ("tablet landscape",CGSize(width:1210,height:834),.init(top:24,bottom:20)),
            ("tablet narrow window",CGSize(width:390,height:834),.init(top:36,bottom:20)),
            ("tablet half window",CGSize(width:600,height:834),.init(top:36,bottom:20)),
            ("tablet wide window",CGSize(width:900,height:600),.init(top:36,bottom:20))]
        for (name,size,inset) in windows {
            let screen = CGRect(origin:.zero,size:size)
            for keyboard in [nil,CGRect(x:0,y:size.height*0.54,width:size.width,height:size.height*0.46)] as [CGRect?] {
                let layout = AdaptiveViewerLayout.conversation(size,inset:inset,keyboard:keyboard)
                check(screen.contains(layout.chat),name+" chat outside window")
                check(screen.contains(layout.stage),name+" model outside window")
                check(layout.chat.width>=290,name+" composer too narrow")
                check(layout.chat.height>=68,name+" composer inaccessible")
                check(layout.chat.minX>=inset.left && layout.chat.maxX<=size.width-inset.right,name+" unsafe horizontal edge")
                if let keyboard { check(layout.chat.maxY<=keyboard.minY,name+" keyboard covers composer") }
                if layout.side {
                    check(layout.stage.maxX<layout.chat.minX,name+" model overlaps chat")
                    check(layout.stage.width>=250,name+" inadequate model space")
                    if let keyboard {check(layout.stage.maxY<keyboard.minY,name+" keyboard covers model composition")}
                }
                let viewport=AdaptiveViewerLayout.normalized(layout.stage,in:size)
                check(CGRect(x:0,y:0,width:1,height:1).insetBy(dx:-0.00001,dy:-0.00001).contains(viewport),name+" invalid bridge viewport")
            }
            for fraction:CGFloat in [0.35,0.70] {
                for keyboard in [nil,CGRect(x:0,y:size.height*0.54,width:size.width,height:size.height*0.46)] as [CGRect?] {
                    let layout=AdaptiveViewerLayout.conversation(size,inset:inset,keyboard:keyboard,heightFraction:fraction)
                    check(screen.contains(layout.chat),name+" adjusted chat outside screen")
                    check(layout.chat.height>=68,name+" adjusted composer inaccessible")
                    if let keyboard {check(layout.chat.maxY<=keyboard.minY,name+" adjusted composer under keyboard")}
                    if !layout.side && keyboard == nil {check(abs(layout.chat.height-size.height*fraction)<1,name+" height preference ignored")}
                }
            }
            for width:CGFloat in [430,460,600] {
                for expanded in [false,true] {
                    let sheet=AdaptiveViewerLayout.sheet(size,inset:inset,preferred:CGSize(width:width,height:420),expanded:expanded)
                    check(screen.contains(sheet),name+" sheet outside window")
                    check(sheet.minX>=inset.left && sheet.maxX<=size.width-inset.right,name+" sheet outside safe width")
                    check(sheet.height>=220,name+" insufficient editor height")
                    if AdaptiveViewerLayout.sideBySide(size) {check(sheet.minX>=size.width*0.4,name+" sheet hides character")}
                }
            }
        }
        let size=CGSize(width:1210,height:834),inset=AdaptiveViewerLayout.Insets(top:24,bottom:20)
        let normal=AdaptiveViewerLayout.conversation(size,inset:inset,keyboard:nil)
        let floating=AdaptiveViewerLayout.conversation(size,inset:inset,keyboard:CGRect(x:930,y:500,width:260,height:250))
        check(normal.stage==floating.stage,"floating keyboard must not resize the whole character")
        check(floating.chat.maxY<500,"floating keyboard occludes composer")
        for (name,size,inset) in windows {
            let compact=AdaptiveViewerLayout.sheet(size,inset:inset,preferred:CGSize(width:600,height:420),expanded:false)
            let expanded=AdaptiveViewerLayout.sheet(size,inset:inset,preferred:CGSize(width:600,height:420),expanded:true)
            let compactAlpha=AdaptiveViewerLayout.sheetSurfaceOpacity(compact,in:size,inset:inset)
            let expandedAlpha=AdaptiveViewerLayout.sheetSurfaceOpacity(expanded,in:size,inset:inset)
            check(compactAlpha == 0,name+" short preview must stay translucent")
            check(expandedAlpha == (AdaptiveViewerLayout.sideBySide(size) ? 0 : 1),name+" expanded surface mismatch")
            var previous:CGFloat = -1
            for t in 0...30 {
                let f=CGFloat(t)/30
                let frame=CGRect(x:compact.minX,y:compact.minY+(expanded.minY-compact.minY)*f,
                    width:compact.width,height:compact.height+(expanded.height-compact.height)*f)
                let alpha=AdaptiveViewerLayout.sheetSurfaceOpacity(frame,in:size,inset:inset)
                check(alpha>=previous && alpha>=0 && alpha<=1,name+" opacity must increase smoothly with expansion")
                previous=alpha
            }
        }
        print("PASS: \(checks) adaptive layout requirements across \(windows.count) window configurations")
    }
}
AdaptiveLayoutChecks.run()
