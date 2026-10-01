import Foundation
import CoreGraphics

@main enum VoiceCaptureStateTests {
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ reason:String) {
            precondition(condition,reason);checks += 1
        }
        // A completed ASR or time limit must never act as a finger release.
        for edit in [false,true] {
            for finalFirst in [false,true] {
                var voice=VoiceCaptureState()
                voice.begin();voice.partial("今天")
                voice.armEdit(true)
                check(voice.phase == .holding,"Hovering cannot open the editor")
                voice.armEdit(edit)
                var sent:[String]=[]
                if finalFirst {
                    if let text=voice.accept(" 今天下雨了 ") {sent.append(text)}
                    check(sent.isEmpty && voice.phase == .holding,"Early ASR completion must keep holding")
                }
                if let text=voice.release(edit:voice.editArmed) {sent.append(text)}
                if edit {
                    check(voice.phase == .editing,"Release in the target opens the editor without waiting for final ASR")
                } else if !finalFirst {
                    check(voice.phase == .finishing,"A normal release waits for final ASR")
                }
                if !finalFirst,let text=voice.accept(" 今天下雨了 ") {sent.append(text)}
                check(sent == (edit ? [] : ["今天下雨了"]),"Only a released send may publish one message")
                check(voice.text=="今天下雨了","Final transcription is normalized")
                check(voice.accept("重复结束")==nil && voice.release(edit:false)==nil,"Repeated callbacks cannot send twice")
            }
        }
        var voice=VoiceCaptureState()
        voice.begin();voice.partial("今天");voice.release(edit:true);voice.edit("今天不下雨")
        check(voice.accept("今天下雨")==nil && voice.text=="今天不下雨","A late final cannot replace a manual correction")
        voice.partial("迟来的片段")
        check(voice.text=="今天不下雨","Late partials cannot overwrite edited text")
        voice.cancel();voice.begin();voice.partial("不完整");voice.release(edit:true);voice.edit("")
        _=voice.accept("不完整的句子")
        check(voice.text.isEmpty && voice.phase == .editing,"Deleting all text is an intentional edit")

        for released in [false,true] {
            voice.cancel();voice.begin();voice.partial("网络中断前的话")
            if released {voice.release(edit:false)}
            voice.recover("网络中断前的话")
            check(voice.phase == (released ? .editing : .holding),"Failure cannot dismiss the held surface")
            check(voice.release(edit:false)==nil && voice.phase == .editing,"An incomplete result always requires review")
            check(voice.text=="网络中断前的话","Failure retains recognized words")
        }
        voice.cancel();voice.begin();voice.recover("")
        check(voice.phase == .holding && voice.needsReview,"An empty failure stays visible until release")
        check(voice.release(edit:false)==nil && voice.phase == .editing,"An empty failure cannot create a blank message")
        voice.cancel();voice.begin();voice.partial("用户文本");voice.release(edit:true);voice.edit("用户修正")
        voice.recover("服务端文本")
        check(voice.text=="用户修正","A failed request cannot overwrite a correction either")
        voice.cancel()
        check(voice.accept("取消后到达")==nil && !voice.active,"Cancellation invalidates late completion")
        voice.partial("取消后的部分结果");voice.recover("取消后的超时")
        check(!voice.active && voice.text.isEmpty,"Late partial/error callbacks cannot resurrect the UI")
        voice.begin();voice.release(edit:false)
        check(voice.accept(" \n ")==nil && !voice.active,"Silence never sends an empty message")
        voice.begin();voice.partial(String(repeating:"声",count:600))
        check(voice.text.count==500,"Streaming text remains bounded")
        voice.cancel();voice.begin()
        check(voice.text.isEmpty && !voice.resultReady && !voice.needsReview && !voice.editArmed,"Every capture starts clean")

        for finalFirst in [false,true] {
            voice.cancel();voice.begin();voice.partial("不发送的内容")
            if finalFirst {_=voice.accept("完整的不发送内容")}
            voice.armCancel(true)
            check(voice.phase == .holding && voice.cancelArmed && !voice.editArmed,"Cancel hover never stops a held recording")
            check(voice.release(edit:false)==nil && !voice.active && voice.text.isEmpty,"Cancel release discards recognized words")
            check(voice.accept("迟到的最终内容")==nil,"Cancelled capture cannot send a late result")
        }
        voice.begin();voice.armCancel(true);voice.armEdit(true)
        check(voice.editArmed && !voice.cancelArmed,"Moving from cancel to edit selects only editing")
        voice.armCancel(true)
        check(voice.cancelArmed && !voice.editArmed,"Moving back selects only cancellation")
        voice.armCancel(false);voice.partial("仍然发送")
        voice.release(edit:false)
        check(voice.accept("仍然发送")=="仍然发送","Sliding out of both zones restores send-on-release")

        // Use the actual visible target, not a fixed distance from the input.
        for frame in [CGRect(x:42,y:628,width:306,height:46),CGRect(x:708,y:414,width:404,height:40)] {
            let inside=CGPoint(x:frame.midX,y:frame.midY)
            check(VoiceEditHitTarget.contains(inside,frame:frame,armed:false),"Phone and tablet target centers arm editing")
            let edge=CGPoint(x:frame.midX,y:frame.maxY+10)
            check(!VoiceEditHitTarget.contains(edge,frame:frame,armed:false),"Approaching the target does not arm prematurely")
            check(VoiceEditHitTarget.contains(edge,frame:frame,armed:true),"Small finger jitter retains the selected target")
            check(!VoiceEditHitTarget.contains(CGPoint(x:frame.midX,y:frame.maxY+30),frame:frame,armed:true),"Sliding back out returns to send")
        }
        check(!VoiceEditHitTarget.contains(.zero,frame:.zero,armed:true),"An unmeasured target cannot select editing")
        print("PASS: \(checks) voice capture ordering, recovery, correction and edit-target checks")
    }
}
