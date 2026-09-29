using System;
using UnityEngine;

namespace ModelSpace
{
    // Angles are relative to the animated upper torso, not world Euler angles.
    // Product comfort limits, deliberately below extreme anatomical ranges.
    public static class GazeMath
    {
        public const float HeadYaw = 50, HeadUp = 22, HeadDown = 28;
        public const float EyeYaw = 12, EyeUp = 8, EyeDown = 10;
        public static Vector2 Angles(Vector3 direction)
        {
            if (direction.sqrMagnitude < .000001f) return Vector2.zero;
            return new Vector2(Mathf.Atan2(direction.x,direction.z)*Mathf.Rad2Deg,
                Mathf.Atan2(direction.y,new Vector2(direction.x,direction.z).magnitude)*Mathf.Rad2Deg);
        }
        public static Vector3 Direction(Vector2 angles) => Quaternion.Euler(-angles.y,angles.x,0)*Vector3.forward;
        public static float Ease(float t) { t = Mathf.Clamp01(t); return t*t*(3-2*t); }
        public static float Availability(Vector2 angles) =>
            (1-Ease((Mathf.Abs(angles.x)-65)/40)) * (1-Ease((Mathf.Abs(angles.y)-40)/25));
        public static Vector2 Limit(Vector2 value,float yaw,float up,float down)
        {
            float radius = new Vector2(value.x/yaw,value.y/(value.y>=0?up:down)).magnitude;
            return radius>1 ? value/radius : value;
        }
        // Exact critically damped spring; no overshoot at the anatomical stops.
        public static void Follow(ref Vector2 value,ref Vector2 velocity,Vector2 target,float speed,float dt)
        {
            dt = Mathf.Clamp(dt,0,1f/20);
            Vector2 offset = value-target, j = velocity+speed*offset;
            float decay = Mathf.Exp(-speed*dt);
            value = target+(offset+j*dt)*decay;
            velocity = (velocity-speed*j*dt)*decay;
        }
    }

    [Serializable] public sealed class GazeState
    {
        public int revision = 1;
        public string action;
        public bool available, independentEyes;
        public float weight, targetYaw, targetPitch, headYaw, headPitch, eyeYaw, eyePitch, eyeError;
        public int headReactionCount;
        public float headReactionPeak, headReactionYaw;
    }

    // Animation -> speech accent (50) -> gaze (80) -> Miku hair collisions (100).
    // Restore unkeyed neck/eye bones before the next animation evaluation; no cumulative twist.
    [DefaultExecutionOrder(80)]
    public sealed class CharacterGaze : MonoBehaviour
    {
        struct Bone
        {
            public Transform transform;
            public Quaternion original;
            public Vector3 forward;
            public void Capture() { if(transform) original=transform.localRotation; }
            public void Restore() { if(transform) transform.localRotation=original; }
        }
        Transform character, body;
        Camera camera;
        CharacterActions actions;
        Bone neck, head, leftEye, rightEye;
        Quaternion bodyBasis;
        Vector2 headOffset,headVelocity,leftOffset,leftVelocity,rightOffset,rightVelocity;
        bool applied;
        float headReactionStart = -100;
        bool headReacting;
        public Action OnHeadReactionCompleted;
        CharacterManifest manifest;
        public float Attention { get; set; } = 1;
        public CharacterPerformanceDriver Performance { get; set; }
        public GazeState State { get; } = new GazeState();
        public void Bind(Transform model,Camera view,CharacterActions actionSource)
        {
            RestorePose(); character=model; camera=view; actions=actionSource;
            manifest=model.GetComponent<ViewerCharacter>().Manifest; Attention=1;
            var rig=manifest.rig;
            Transform h=CharacterContract.Resolve(model,rig.head),n=CharacterContract.Resolve(model,rig.neck),
                l=CharacterContract.Resolve(model,rig.leftEye),r=CharacterContract.Resolve(model,rig.rightEye);
            if(n && h && !h.IsChildOf(n)) n=null;
            body=n ? n.parent : h ? h.parent : null;
            bodyBasis=body ? Quaternion.Inverse(body.rotation) : Quaternion.identity;
            head=MakeBone(h); neck=MakeBone(n); leftEye=MakeBone(l); rightEye=MakeBone(r);
            headOffset=headVelocity=leftOffset=leftVelocity=rightOffset=rightVelocity=Vector2.zero;
            State.available=manifest.Supports("core.gaze@1") && h && body;
            State.independentEyes=State.available && l && r; State.weight=0;
            State.action=""; State.targetYaw=State.targetPitch=State.headYaw=State.headPitch=State.eyeYaw=State.eyePitch=State.eyeError=0;
            headReactionStart=-100; headReacting=false; State.headReactionCount=0; State.headReactionPeak=State.headReactionYaw=0;
        }
        // An intentional touch owns a short additive head/neck response. It does
        // not compete with the whole-body animation lease or get cancelled by TTS.
        public bool ReactToHeadTouch()
        {
            // Do not restart a visible response halfway through a turn: repeated
            // finger taps must not snap the head back to the first frame.
            if(!State.available || headReacting) return false;
            headReactionStart=Time.unscaledTime; headReacting=true; State.headReactionCount++; State.headReactionPeak=0;
            return true;
        }
        public static Vector2 TouchReaction(float elapsed)
        {
            const float duration=1.8f;
            if(elapsed<0 || elapsed>=duration) return Vector2.zero;
            float envelope=GazeMath.Ease(elapsed/.18f)*GazeMath.Ease((duration-elapsed)/.42f);
            return new Vector2(16*Mathf.Sin(elapsed/duration*Mathf.PI*4)*envelope,
                -2.5f*Mathf.Sin(elapsed/duration*Mathf.PI)*envelope);
        }
        Bone MakeBone(Transform t) => new Bone { transform=t, original=t?t.localRotation:Quaternion.identity,
            forward=t ? Quaternion.Inverse(t.rotation)*Vector3.forward : Vector3.forward };
        void Update() { RestorePose(); }
        void LateUpdate() { Step(Time.unscaledDeltaTime,actions ? actions.CurrentAction : ""); }
        void OnDisable() { RestorePose(); }
        public void RestorePose()
        {
            if(!applied) return;
            neck.Restore(); head.Restore(); leftEye.Restore(); rightEye.Restore(); applied=false;
        }
        public void Step(float dt,string action)
        {
            if(!State.available || !camera || !character || !character.gameObject.activeInHierarchy) return;
            // Each call requires the restored / freshly sampled animation pose.
            neck.Capture(); head.Capture(); leftEye.Capture(); rightEye.Capture(); applied=true;
            var basis=body.rotation*bodyBasis;
            Vector3 origin=State.independentEyes ? (leftEye.transform.position+rightEye.transform.position)*.5f : head.transform.position;
            var target=GazeMath.Angles(Quaternion.Inverse(basis)*(camera.transform.position-origin));
            float availability=GazeMath.Availability(target);
            // Bow intentionally looks down. A head shake keeps its authored amplitude and softens eye contact.
            var mode=manifest.Action(action)?.gaze ?? actions?.Posture?.Definition?.gaze ?? "follow";
            float performanceWeight=Performance?Performance.GazeWeight:1;
            float attention=(mode=="release" ? 0 : 1)*Attention*performanceWeight;
            var share=State.independentEyes ? new Vector2(.8f,.75f) : Vector2.one;
            var desired=GazeMath.Limit(Vector2.Scale(target,share),manifest.gaze.yaw,manifest.gaze.up,manifest.gaze.down)*availability*attention;
            GazeMath.Follow(ref headOffset,ref headVelocity,desired,10,dt);
            Vector3 animatedForward=head.transform.rotation*head.forward;
            var animatedAngles=GazeMath.Angles(Quaternion.Inverse(basis)*animatedForward);
            float preserve=(mode=="soft" || mode=="release") ? 1 : Mathf.Lerp(1,.3f,availability);
            // Author poses can put the head outside the standing gaze envelope (sleep,
            // crouch). Fade the entire correction out; merely setting Attention=0 would
            // still clamp the authored pose and force the sleeping head toward upright.
            var resting=GazeMath.Limit(headOffset+animatedAngles*preserve,manifest.gaze.yaw,manifest.gaze.up,manifest.gaze.down);
            var reaction=TouchReaction(Time.unscaledTime-headReactionStart);
            var final=GazeMath.Limit(resting+reaction,manifest.gaze.yaw,manifest.gaze.up,manifest.gaze.down);
            State.headReactionYaw=final.x-resting.x;
            State.headReactionPeak=Mathf.Max(State.headReactionPeak,Mathf.Abs(State.headReactionYaw));
            Vector3 direction=basis*GazeMath.Direction(final);
            Quaternion correction=Quaternion.Slerp(Quaternion.identity,Quaternion.FromToRotation(animatedForward,direction),performanceWeight);
            if(neck.transform) neck.transform.rotation=Quaternion.Slerp(Quaternion.identity,correction,.25f)*neck.transform.rotation;
            head.transform.rotation=Quaternion.Slerp(Quaternion.identity,Quaternion.FromToRotation(head.transform.rotation*head.forward,direction),performanceWeight)*head.transform.rotation;
            float eyeAttention=availability*attention*(mode=="soft"?.35f:1);
            var left=ApplyEye(leftEye,ref leftOffset,ref leftVelocity,eyeAttention,dt);
            var right=ApplyEye(rightEye,ref rightOffset,ref rightVelocity,eyeAttention,dt);
            State.weight=availability*attention; State.targetYaw=target.x; State.targetPitch=target.y;
            State.action=action;
            var measured=GazeMath.Angles(Quaternion.Inverse(basis)*(head.transform.rotation*head.forward));
            State.headYaw=measured.x; State.headPitch=measured.y;
            State.eyeYaw=(leftOffset.x+rightOffset.x)*.5f; State.eyePitch=(leftOffset.y+rightOffset.y)*.5f;
            State.eyeError=State.independentEyes ? Mathf.Max(left,right) : Vector3.Angle(direction,camera.transform.position-origin);
            if(headReacting && Time.unscaledTime-headReactionStart>=1.8f) { headReacting=false;OnHeadReactionCompleted?.Invoke(); }
        }
        float ApplyEye(Bone bone,ref Vector2 offset,ref Vector2 velocity,float weight,float dt)
        {
            if(!bone.transform) return 0;
            Vector3 forward=bone.transform.rotation*bone.forward;
            Quaternion frame=Quaternion.LookRotation(forward,head.transform.up);
            Vector3 target=camera.transform.position-bone.transform.position;
            var angles=GazeMath.Angles(Quaternion.Inverse(frame)*target);
            var desired=GazeMath.Limit(angles,manifest.gaze.eyeYaw,manifest.gaze.eyeUp,manifest.gaze.eyeDown)*weight;
            GazeMath.Follow(ref offset,ref velocity,desired,26,dt);
            offset=GazeMath.Limit(offset,manifest.gaze.eyeYaw,manifest.gaze.eyeUp,manifest.gaze.eyeDown);
            bone.transform.rotation=Quaternion.FromToRotation(forward,frame*GazeMath.Direction(offset))*bone.transform.rotation;
            return Vector3.Angle(bone.transform.rotation*bone.forward,target);
        }
    }
}
