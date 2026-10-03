import UIKit
import UIKit.UIGestureRecognizerSubclass

enum CharacterPreviewOrigin { case character, conversationBlank, conversationMessage }

/// Direction is decided once after a small movement threshold. On a message,
/// diagonal/vertical movement fails early so native scrolling keeps its momentum.
private final class CharacterPreviewGesture: UIGestureRecognizer {
    private var fingers:[UITouch] = []
    private var distance:CGFloat = 1
    var source = CharacterPreviewOrigin.character
    var rejectsAdditionalTouch=false
    var hasFinger:Bool { !fingers.isEmpty }
    private(set) var isPinching=false
    private(set) var zoom:CGFloat=1
    private(set) var origin = CGPoint.zero
    private(set) var rotation = CGPoint.zero
    private(set) var edgeRatio:CGFloat=0
    private(set) var horizontalSpeed:CGFloat=0
    private var samplePoint=CGPoint.zero
    private var sampleTime:TimeInterval=0
    private func activeFingers(in event:UIEvent)->Int {
        event.allTouches?.filter { $0.window === view?.window && $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent) {
        guard state == .possible || state == .began || state == .changed else {return}
        // UIKit can reset a failed ancestor recognizer and offer the next finger
        // while the previous finger is still down. Inspect the whole event,
        // not only this recognizer's newly delivered touches.
        guard !rejectsAdditionalTouch,activeFingers(in:event)==fingers.count+touches.count,
              fingers.count+touches.count<=2 else {
            state = state == .possible ? .failed : .cancelled;return
        }
        fingers.append(contentsOf:touches)
        if fingers.count==1 {origin=fingers[0].location(in:view);samplePoint=origin;sampleTime=fingers[0].timestamp;return}
        let a=fingers[0].location(in:view),b=fingers[1].location(in:view)
        origin=CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
        distance=max(12,hypot(a.x-b.x,a.y-b.y));rotation = .zero;zoom=1;isPinching=true
        // One recognizer owns both modes, so a second finger can take over an
        // already recognized turn without fighting the conversation scroll.
        if state != .possible {state = .changed}
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent) {
        guard state == .possible || state == .began || state == .changed,let finger=fingers.first,let view else {return}
        guard activeFingers(in:event)==fingers.count else {state = state == .possible ? .failed : .cancelled;return}
        if isPinching {
            guard fingers.count==2 else {state = .cancelled;return}
            let a=finger.location(in:view),b=fingers[1].location(in:view)
            zoom=min(2,max(0.5,hypot(a.x-b.x,a.y-b.y)/distance))
            state = state == .possible ? .began : .changed;return // Centroid movement and two-finger twist are ignored.
        }
        let point=finger.location(in:view),dx=point.x-origin.x,dy=point.y-origin.y
        let dt=finger.timestamp-sampleTime
        if dt>0 {
            let speed=abs(point.x-samplePoint.x)/max(1,view.bounds.width)/max(1.0/240,dt)
            let weight=1-exp(-dt/0.045)
            horizontalSpeed += (min(4,speed)-horizontalSpeed)*weight
            samplePoint=point;sampleTime=finger.timestamp
        }
        guard state != .possible || hypot(dx,dy)>=7 else {return}
        if state == .possible,source == .conversationMessage,abs(dx)<=abs(dy)*1.2 {
            state = .failed;return
        }
        rotation=CGPoint(x:dx/max(1,view.bounds.width),y:dy/max(1,view.bounds.height))
        let margin:CGFloat=16
        let edge=dx>=0 ? view.bounds.width-max(margin,view.safeAreaInsets.right) : max(margin,view.safeAreaInsets.left)
        let span=max(24,abs(edge-origin.x))
        edgeRatio=min(1,max(-1,dx/span))
        state = state == .possible ? .began : .changed
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent) {
        guard state == .possible || state == .began || state == .changed else {return}
        state = state == .possible ? .failed : .ended
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent) {
        guard state == .possible || state == .began || state == .changed else {return}
        state = state == .possible ? .failed : .cancelled
    }
    override func reset() {fingers.removeAll();origin = .zero;rotation = .zero;zoom=1;edgeRatio=0;horizontalSpeed=0;sampleTime=0;samplePoint = .zero;isPinching=false;rejectsAdditionalTouch=false;super.reset()}
}

/// Enabled only by the position button. Finger-count changes start a new basis,
/// so adding/removing a finger never mixes rotation with translation or zoom.
private final class CharacterEditGesture: UIGestureRecognizer {
    private var fingers:[UITouch] = []
    private var anchor = CGPoint.zero
    private var distance:CGFloat = 1
    private(set) var rotation = CGPoint.zero
    private(set) var translation = CGPoint.zero
    private(set) var zoom:CGFloat = 1
    private(set) var rebased = false
    var transforms:Bool { fingers.count == 2 }
    private func rebase() {
        let p=fingers.map{$0.location(in:view)}
        guard let first=p.first else {return}
        anchor=p.count==1 ? first : CGPoint(x:(first.x+p[1].x)/2,y:(first.y+p[1].y)/2)
        distance=p.count==1 ? 1 : max(12,hypot(first.x-p[1].x,first.y-p[1].y))
        rotation = .zero;translation = .zero;zoom=1;rebased=true
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent) {
        guard state == .possible || state == .began || state == .changed else {return}
        guard fingers.count+touches.count<=2 else {state = .cancelled;return}
        fingers.append(contentsOf:touches);rebase()
        // A single resting finger is still a tap. Recognize a drag only after
        // movement, or a transform as soon as the second finger arrives.
        if fingers.count==2 {state = state == .possible ? .began : .changed}
        else if state != .possible {state = .changed}
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent) {
        guard state == .possible || state == .began || state == .changed else {return}
        let p=fingers.map{$0.location(in:view)}
        guard let first=p.first,let view else {return}
        if state == .possible,p.count==1,hypot(first.x-anchor.x,first.y-anchor.y)<6 {return}
        rebased=false
        let width=max(1,view.bounds.width),height=max(1,view.bounds.height)
        if p.count==1 {
            rotation=CGPoint(x:(first.x-anchor.x)/width,y:(first.y-anchor.y)/height)
        } else {
            let center=CGPoint(x:(first.x+p[1].x)/2,y:(first.y+p[1].y)/2)
            translation=CGPoint(x:min(1,max(-1,(center.x-anchor.x)/width)),y:min(1,max(-1,(center.y-anchor.y)/height)))
            zoom=min(2,max(0.5,hypot(first.x-p[1].x,first.y-p[1].y)/distance))
        }
        state = state == .possible ? .began : .changed
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent) {
        guard state == .possible || state == .began || state == .changed else {return}
        fingers.removeAll{touches.contains($0)}
        if state == .possible {state = .failed}
        else if fingers.isEmpty {state = .ended} else {rebase();state = .changed}
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent) {state = state == .possible ? .failed : .cancelled}
    override func reset() {fingers.removeAll();rotation = .zero;translation = .zero;zoom=1;rebased=false;super.reset()}
}

final class CharacterTouchSurface:UIView,UIGestureRecognizerDelegate {
    var onGesture:(([String:Any])->Void)?
    private var acceptsEdit:((CGPoint,UIView?)->Bool)?
    private var previewOrigin:((CGPoint,UIView?)->CharacterPreviewOrigin?)?
    private var isConversationScroll:((UIView)->Bool)?
    var inputAvailable:Bool {isUserInteractionEnabled && window != nil}
    private(set) var touchSequences=0
    private(set) var recognizedGestures=0
    private(set) var inspectionInProgress=false
    private(set) var editing=false
    private static var nextToken=0
    private(set) var inspectionToken=0
    private var previewToken=0
    private var previewInProgress=false
    private var previewAction="previewRotate"
    private lazy var tap=UITapGestureRecognizer(target:self,action:#selector(tapped(_:)))
    private lazy var preview=CharacterPreviewGesture(target:self,action:#selector(previewed(_:)))
    private lazy var inspect=CharacterEditGesture(target:self,action:#selector(inspected(_:)))
    override init(frame:CGRect) {
        super.init(frame:frame)
        backgroundColor = .clear;isOpaque=false;isMultipleTouchEnabled=true
        addGestureRecognizer(tap);addGestureRecognizer(preview);addGestureRecognizer(inspect);inspect.isEnabled=false
        tap.require(toFail:preview)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    func observeEditing(in overlay:UIView,accepts:@escaping(CGPoint,UIView?)->Bool) {
        inspect.view?.removeGestureRecognizer(inspect);acceptsEdit=accepts;inspect.delegate=self;overlay.addGestureRecognizer(inspect)
    }
    func coordinateDismissTap(_ recognizer:UIGestureRecognizer) {recognizer.require(toFail:inspect)}
    func isEditingGesture(_ recognizer:UIGestureRecognizer)->Bool {recognizer === inspect}
    func observePreview(in overlay:UIView,origin:@escaping(CGPoint,UIView?)->CharacterPreviewOrigin?,
                        conversationScroll:@escaping(UIView)->Bool) {
        preview.view?.removeGestureRecognizer(preview)
        previewOrigin=origin;isConversationScroll=conversationScroll;preview.delegate=self
        overlay.addGestureRecognizer(preview)
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
        if gestureRecognizer === preview {
            guard !editing,isUserInteractionEnabled else {return false}
            // An eligible second finger switches to a scale-only gesture. A
            // finger on a button cancels rather than stealing that control.
            if preview.hasFinger {
                if let source=previewOrigin?(touch.location(in:gestureRecognizer.view),touch.view) {
                    if source != .character {preview.source=source}
                } else {preview.rejectsAdditionalTouch=true}
                return true
            }
            guard let source=previewOrigin?(touch.location(in:gestureRecognizer.view),touch.view) else {return false}
            preview.source=source;return true
        }
        return editing && (acceptsEdit?(touch.location(in:gestureRecognizer.view),touch.view) ?? true)
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldBeRequiredToFailBy other:UIGestureRecognizer)->Bool {
        // Dynamic UIKit failure dependency: the chat scroll waits only for our
        // 7pt direction decision. We never replace UIScrollView's delegate,
        // disable scrolling mid-pan, or forward synthetic scroll offsets.
        guard gestureRecognizer === preview,let scroll=other.view as? UIScrollView,
              other === scroll.panGestureRecognizer else {return false}
        return isConversationScroll?(scroll) ?? false
    }
    func configure(available:Bool,framingEnabled:Bool) {
        if !available {cancelInspection()}
        isUserInteractionEnabled=available;tap.isEnabled=available && !editing;inspect.isEnabled=available && editing
        preview.isEnabled=available && !editing
    }
    func beginEditing() {
        Self.nextToken+=1;inspectionToken=Self.nextToken;editing=true;tap.isEnabled=false;inspect.isEnabled=isUserInteractionEnabled
        preview.isEnabled=false
    }
    func cancelCurrentAdjustment() {inspect.isEnabled=false;inspect.isEnabled=editing && isUserInteractionEnabled}
    func endEditing() {
        // Disabling an in-flight recognizer delivers its final cancellation first.
        inspect.isEnabled=false;editing=false;inspectionInProgress=false;tap.isEnabled=isUserInteractionEnabled
        preview.isEnabled=isUserInteractionEnabled
    }
    func cancelInspection() {preview.isEnabled=false;endEditing()}
    override func didMoveToWindow() {super.didMoveToWindow();if window==nil {cancelInspection()}}
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {touchSequences+=1;super.touchesBegan(touches,with:event)}
    @objc private func tapped(_ recognizer:UITapGestureRecognizer) {
        guard !editing,recognizer.state == .ended,bounds.width>0,bounds.height>0 else {return}
        let point=recognizer.location(in:self);recognizedGestures+=1
        onGesture?(["action":"tap","state":"ended","viewportX":point.x/bounds.width,"viewportY":point.y/bounds.height])
    }
    @objc private func previewed(_ recognizer:CharacterPreviewGesture) {
        guard bounds.width>0,bounds.height>0 else {return}
        let action=recognizer.isPinching ? "previewPinch" : "previewRotate"
        let state:String
        switch recognizer.state {
        case .began:
            guard !editing else {return}
            Self.nextToken+=1;previewToken=Self.nextToken;previewInProgress=true;previewAction=action;recognizedGestures+=1;state="began"
        case .changed:
            guard previewInProgress else {return}
            if previewAction != action {
                onGesture?(["action":previewAction,"state":"cancelled","previewToken":previewToken])
                Self.nextToken+=1;previewToken=Self.nextToken;previewAction=action;recognizedGestures+=1;state="began"
            } else {state="changed"}
        case .ended,.cancelled,.failed:
            guard previewInProgress else {return}
            previewInProgress=false;state=recognizer.state == .ended ? "ended" : "cancelled"
        default:return
        }
        let payload:[String:Any]=["action":previewAction,"state":state,"previewToken":previewToken,
            "viewportX":recognizer.origin.x/bounds.width,"viewportY":recognizer.origin.y/bounds.height,
            "deltaX":recognizer.rotation.x,"deltaY":recognizer.rotation.y,"scale":recognizer.zoom,"previewSpeed":recognizer.horizontalSpeed,
            "previewEdgeMapped":true,"previewEdgeRatio":recognizer.edgeRatio,
            "previewFromConversation":recognizer.source != .character]
        onGesture?(payload)
    }
    @objc private func inspected(_ recognizer:CharacterEditGesture) {
        guard editing else {return}
        let state:String
        switch recognizer.state {
        case .began:state="adjusting";inspectionInProgress=true;recognizedGestures+=1
        case .changed:state=recognizer.rebased ? "adjusting" : "changed"
        case .ended,.cancelled,.failed:state="ended";inspectionInProgress=false
        default:return
        }
        onGesture?(["action":"inspect","state":state,"inspectionToken":inspectionToken,
            "transforming":recognizer.transforms,"deltaX":recognizer.rotation.x,"deltaY":recognizer.rotation.y,
            "translationX":recognizer.translation.x,"translationY":recognizer.translation.y,"scale":recognizer.zoom])
    }
}
