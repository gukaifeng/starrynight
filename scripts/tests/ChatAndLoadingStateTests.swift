import Foundation

@main struct ChatAndLoadingStateTests {
    static func main() {
        var checks = 0
        func check(_ condition:Bool,_ message:String) { precondition(condition,message); checks += 1 }
        var scroll = ConversationScrollState()
        check(!scroll.showsReturnButton && scroll.followingLatest,"Initial conversation follows latest")
        scroll.update(bottomDistance:180)
        check(scroll.followingLatest && !scroll.showsReturnButton,"New streaming text must not switch off automatic follow")
        scroll.update(bottomDistance:18)
        scroll.scrollTowardHistory(); scroll.update(bottomDistance:150)
        check(scroll.showsReturnButton && !scroll.followingLatest,"Dragging into history offers return")
        scroll.update(bottomDistance:240)
        check(scroll.showsReturnButton && !scroll.followingLatest,"Geometry changes alone do not steal the reader's position")
        scroll.update(bottomDistance:40)
        check(scroll.showsReturnButton,"Almost at bottom remains explicit")
        scroll.update(bottomDistance:18)
        check(!scroll.showsReturnButton && scroll.followingLatest,"Manual bottom arrival hides arrow and resumes follow")
        scroll.update(bottomDistance:-30)
        check(!scroll.showsReturnButton,"Bottom overscroll bounce does not resurrect the arrow")
        scroll.scrollTowardHistory()
        check(!scroll.showsReturnButton,"A drag alone cannot show the arrow while latest remains visible")
        scroll.update(bottomDistance:120); scroll.returnToLatest()
        check(!scroll.showsReturnButton && scroll.followingLatest,"Arrow tap hides promptly during animated scroll")
        scroll.scrollTowardHistory(); scroll.update(bottomDistance:180)
        scroll.update(bottomDistance:0)
        check(!scroll.showsReturnButton && scroll.followingLatest,"A taller viewport or smaller text can also reach the bottom")
        let previous = scroll; scroll.update(bottomDistance:.nan)
        check(scroll == previous,"Invalid layout samples do not change state")
        for source in ["user message","AI message","late AI narration"] {
            scroll.scrollTowardHistory(); scroll.update(bottomDistance:480)
            scroll.returnToLatest()
            check(scroll.followingLatest && !scroll.showsReturnButton,"New \(source) resumes following even from history")
            scroll.update(bottomDistance:0)
            check(scroll.isAtLatest,"New \(source) settles at the actual bottom")
        }

        var loading = ModelLoadingPresentation()
        check(!loading.isVisible,"The retained-home path does not start a new arrival")
        loading.begin(now:10)
        check(loading.isVisible,"A new role immediately has a loading canvas")
        check(abs(loading.remainingDisplayTime(now:10.1)-0.55)<0.0001,"A cached new role cannot flash the animation")
        check(abs(loading.remainingDisplayTime(now:10.5)-0.15)<0.0001,"Repeated readiness checks do not restart the minimum")
        check(loading.remainingDisplayTime(now:12)==0,"Long loads reveal immediately when ready")
        loading.begin(now:30)
        check(abs(loading.remainingDisplayTime(now:30.2)-0.45)<0.0001,"A different role starts its own minimum, including after cancellation")
        check(loading.remainingDisplayTime(now:35)==0,"Cold loading has no extra delay after a long initialization")
        print("PASS: \(checks) chat scroll and model-loading state checks")
    }
}
