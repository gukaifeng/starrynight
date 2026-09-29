import Foundation

@main struct HomeCompositionTests {
    @MainActor static func main() {
        var checks=0
        func check(_ condition:Bool,_ description:String) { precondition(condition,description);checks += 1 }
        let destinations=CustomizationDestination.allCases
        check(Set(destinations)==Set(CustomizationDestination.allCases),"The unified panel has a route to every supported settings page")
        check(destinations.count==Set(destinations).count,"Settings are not duplicated between categories")
        check(Set(destinations) == Set([.music,.memory,.history]),"Only music, memory and chat data remain listener editable")
        let child=SoftPanelCloseRequest(), parent=SoftPanelCloseRequest()
        var valid=false, saves=0, returns=0, dismissals=0
        child.begin { returns += 1 }
        child.beforeClose = { if valid { saves += 1 }; return valid }
        parent.begin { dismissals += 1 }
        parent.beforeClose = { child.beforeClose?() ?? true }
        child.request()
        check(returns==0 && saves==0,"Invalid child draft cannot return silently")
        parent.request()
        check(dismissals==0 && saves==0,"Outside dismissal cannot bypass child validation")
        valid=true;child.request()
        check(returns==1 && saves==1,"Back saves the active draft before returning")
        child.request()
        check(returns==1 && saves==1,"Repeated taps cannot submit twice")
        child.beforeClose=nil;parent.request()
        check(dismissals==1,"Overview can close after the child has saved")
        parent.request()
        check(dismissals==1,"Repeated outside taps cannot dismiss twice")
        parent.begin { dismissals += 1 }
        let next=SoftPanelCloseRequest()
        next.beforeClose={ saves += 1;return true }
        parent.beforeClose={ next.beforeClose?() ?? true }
        child.beforeClose=nil // The outgoing page finishes its fade after the next page starts.
        parent.request()
        check(saves==2 && dismissals==2,"Old page cleanup must not clear a new page's validation")
        print("PASS: \(checks) customization routing and close validation checks")
    }
}
