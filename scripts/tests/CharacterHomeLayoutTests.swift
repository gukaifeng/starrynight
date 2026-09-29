import Foundation
import CoreGraphics

@main struct CharacterHomeLayoutTests {
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ label:String) { precondition(condition,label);checks += 1 }
        for width in [CGFloat(240),300,350,390,550,770,1024,1180] {
            for height in [CGFloat(110),180,260,420,570,760,1000] {
                for count in [1,4,5,9,16,29] {
                    for large in [false,true] {
                        let layout=CharacterHomeLayout(size:CGSize(width:width,height:height),count:count,largeText:large)
                        check(layout.card.width>0 && layout.card.height>0,"Positive card bounds")
                        check(layout.card.width*CGFloat(layout.columns)+layout.gap*CGFloat(layout.columns-1)<=width+0.01,"No horizontal overflow")
                        check(layout.gridHeight<=height+0.01,"No vertical overflow")
                        check(layout.pages*layout.capacity>=count,"Every character is reachable")
                        for index in 0..<count {
                            let page=layout.page(containing:index)
                            check(page>=0 && page<layout.pages && index>=page*layout.capacity && index<(page+1)*layout.capacity,"Selected character stays on the restored page")
                        }
                    }
                }
            }
        }
        let phone=CharacterHomeLayout(size:CGSize(width:362,height:570),count:4)
        check(phone.columns==2 && phone.rows==2 && phone.pages==1,"Phone portrait uses four readable cards")
        let tablet=CharacterHomeLayout(size:CGSize(width:770,height:920),count:4)
        check(tablet.columns==2 && tablet.rows==2,"Tablet portrait balances four characters into two rows")
        let wide=CharacterHomeLayout(size:CGSize(width:1130,height:510),count:4)
        check(wide.columns==4 && wide.rows==1,"Tablet landscape uses the available width")
        let short=CharacterHomeLayout(size:CGSize(width:320,height:260),count:4)
        check(short.pages>1,"Short window uses real pages instead of clipping")
        let paged=CharacterHomeLayout(size:CGSize(width:320,height:260),count:9)
        check(paged.page(after:0,translation:80,predicted:180,width:320)==0,"Leading overscroll stays on first page")
        check(paged.page(after:paged.pages-1,translation:-90,predicted:-180,width:320)==paged.pages-1,"Trailing overscroll stays on last page")
        check(paged.page(after:1,translation:-100,predicted:-900,width:320)==2,"A fast swipe advances only one page")
        check(paged.page(after:1,translation:4,predicted:8,width:320)==1,"An incidental brush does not turn a page")
        check(paged.page(after:1,translation:100,predicted:200,width:320)==0,"Reverse swipe goes to the previous page")
        print("PASS: \(checks) adaptive gallery layout checks")
    }
}
