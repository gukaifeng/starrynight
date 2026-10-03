using System;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class HostEmotionMotionState
    {
        public int revision=2,started,completed,gestureCount=10;
        public bool supported,enabled,suppressed;
        public string gesture="",expression="",origin="starrynight.host-emotion.v2.developer-preview";
        public string[] expressions=Array.Empty<string>();
        public float weight,progress,peakDegrees;
    }

    // Optional, masked additive upper-body animation AFTER author animation and
    // gaze, BEFORE cloth/hair. Calibrated facial morphs are also overlaid, but
    // never speech visemes. No root, legs, fingers, scale or camera writes.
    // All offsets unwind before the next animation sample; cancellation also has
    // an explicit C2 release, so turning the experiment off never pops the pose.
    [DefaultExecutionOrder(90)]
    public sealed class HostEmotionMotion : MonoBehaviour
    {
        public static readonly string[] Gestures={"agree","happy","curious","shy","pout","sad","surprised","welcome","encourage","disagree"};
        public HostEmotionMotionState State {get;private set;}=new HostEmotionMotionState();
        public Action OnChanged;
        HostEmotionRig rig;
        ViewerCharacter character;
        CharacterActions actions;
        AvatarControlDriver author;
        Quaternion[] before=Array.Empty<Quaternion>();
        HostEmotionRig.Face face;
        float[] faceBefore=Array.Empty<float>();
        struct Guard {public int hash;public string kind;public float initial;}
        Guard[] guards=Array.Empty<Guard>();
        bool applied,interacting,reportedPose;
        string queued="";
        float elapsed,gap,intensity=1,release=-1,releaseStart=1;
        public void Bind(ViewerCharacter actor,CharacterActions source)
        {
            Clear();character=actor;actions=source;rig=actor.GetComponent<HostEmotionRig>();
            author=actor.GetComponent<AvatarControlDriver>();
            State=new HostEmotionMotionState {supported=rig && rig.joints.Length>=10,
                expressions=rig?Array.ConvertAll(rig.faces,f=>f.gesture+" · "+f.label):Array.Empty<string>()};
            before=new Quaternion[rig?rig.joints.Length:0];
            var list=new List<Guard>();
            if(rig && author)foreach(string name in rig.blockingParameters) {
                var p=Array.Find(author.profile.parameters,x=>x.name==name);
                if(p!=null)list.Add(new Guard {hash=Animator.StringToHash(name),kind=p.kind,initial=p.initial});
            }
            guards=list.ToArray();
            var restore=GetComponent<HostEmotionMotionRestore>() ?? gameObject.AddComponent<HostEmotionMotionRestore>();
            restore.driver=this;
        }
        public void Clear()
        {
            RestorePose();rig=null;character=null;author=null;queued="";
            elapsed=gap=0;release=-1;interacting=false;State=new HostEmotionMotionState();
            face=null;faceBefore=Array.Empty<float>();
        }
        public void Configure(bool value)
        {
            State.enabled=value && State.supported;
            if(!State.enabled)Cancel();
        }
        public void SetInteracting(bool value) {interacting=value;}
        public void Cancel()
        {
            queued="";
            if(State.gesture.Length>0 && release<0) {release=0;releaseStart=State.weight;}
        }
        public static string ForIntent(string intent)
        {
            switch(intent) {
                case "soft_smile":case "happy":case "proud":case "playful":return "happy";
                case "curious":case "confused":return "curious";
                case "shy":return "shy";
                case "pout":case "angry":return "pout";
                case "sad":case "worried":return "sad";
                case "surprised":case "surprise":return "surprised";
                default:return ""; // Unknown future emotions never guess a body action.
            }
        }
        public string CueOriginalExpression(string option)
        {
            // This revision is an inspection experiment. Promotion to automatic
            // conversation requires the user's visual approval in a later change.
            return "HOST_MOTION_DEVELOPER_ONLY";
        }
        public string Request(string gesture,bool preview)
        {
            if(!State.supported)return "HOST_MOTION_UNSUPPORTED";
            if(!State.enabled)return "HOST_MOTION_DISABLED";
            if(!preview)return "HOST_MOTION_DEVELOPER_ONLY";
            if(Array.IndexOf(Gestures,gesture)<0)return "HOST_MOTION_UNKNOWN";
            if(Blocked())return "HOST_MOTION_AUTHOR_PRIORITY";
            if(State.gesture.Length>0 || gap>0) {
                // A bounded latest-only queue; speech can never build a backlog.
                if(gesture!=State.gesture || preview)queued=gesture;
                if(preview) {Cancel();queued=gesture;}
                return null;
            }
            StartGesture(gesture);return null;
        }
        void StartGesture(string gesture)
        {
            State.gesture=gesture;elapsed=0;release=-1;State.weight=1;
            State.progress=State.peakDegrees=0;State.started++;reportedPose=false;
            face=Array.Find(rig.faces,f=>f.gesture==gesture);faceBefore=new float[face?.indices.Length ?? 0];
            State.expression=face?.label ?? "中性表情";
            // Stable alternation keeps a replay auditable, without frame-dependent noise.
            intensity=(State.started%2==0?.94f:1)*rig.amplitude;
        }
        bool Blocked()
        {
            if(character && character.GetComponent<SourceMotionPreview>()?.Active==true)return true;
            if(interacting || (actions && (!string.IsNullOrEmpty(actions.CurrentAction) ||
               (actions.Posture && (actions.Posture.State.id!="stand" || actions.Posture.State.transitioning)))))return true;
            if(author)foreach(var guard in guards) {
                float value=guard.kind=="bool" || guard.kind=="trigger"?(author.animator.GetBool(guard.hash)?1:0):
                    guard.kind=="int"?author.animator.GetInteger(guard.hash):author.animator.GetFloat(guard.hash);
                if(Mathf.Abs(value-guard.initial)>.001f)return true;
            }
            return false;
        }
        void LateUpdate(){Step(Time.unscaledDeltaTime);}
        void OnDisable(){RestorePose();Cancel();}
        public void Step(float dt)
        {
            RestorePose();
            if(!State.supported || !character || !character.gameObject.activeInHierarchy)return;
            dt=Mathf.Clamp(dt,0,.05f);
            bool wasSuppressed=State.suppressed;State.suppressed=Blocked();
            if(wasSuppressed!=State.suppressed)OnChanged?.Invoke();
            if(State.suppressed || !State.enabled)Cancel();
            gap=Mathf.Max(0,gap-dt);
            if(State.gesture.Length==0) {
                if(State.enabled && !State.suppressed && gap==0 && queued.Length>0) {
                    var next=queued;queued="";StartGesture(next);
                } else return;
            }
            elapsed+=dt;
            float duration=Duration(State.gesture);State.progress=Mathf.Clamp01(elapsed/duration);
            if(release>=0) {release+=dt;State.weight=releaseStart*(1-Smooth(release/.48f));}
            if(elapsed>=duration || (release>=.48f)) {
                State.completed++;State.gesture=State.expression="";State.weight=0;State.progress=1;gap=.18f;release=-1;OnChanged?.Invoke();return;
            }
            if(face!=null){
                float faceWeight=Pulse(elapsed/duration,.04f,.3f,.62f,1)*State.weight;
                for(int i=0;i<face.indices.Length;i++){var skin=face.skins[i];faceBefore[i]=skin.GetBlendShapeWeight(face.indices[i]);skin.SetBlendShapeWeight(face.indices[i],Mathf.Lerp(faceBefore[i],face.values[i],faceWeight));}
            }
            for(int i=0;i<rig.joints.Length;i++) {
                var j=rig.joints[i];before[i]=j.bone.localRotation;
                var euler=Sample(State.gesture,j.human,elapsed)*intensity*State.weight;
                if(j.human.EndsWith("Shoulder",StringComparison.Ordinal) || j.human.EndsWith("UpperArm",StringComparison.Ordinal))
                    euler.z*=j.lateralSign*(j.human.StartsWith("Left",StringComparison.Ordinal)?1:-1);
                var delta=j.elbowAxis.sqrMagnitude>.9f?Quaternion.AngleAxis(-euler.x,j.elbowAxis):
                    j.axes*Quaternion.Euler(euler)*Quaternion.Inverse(j.axes);
                j.bone.localRotation=before[i]*delta;
                State.peakDegrees=Mathf.Max(State.peakDegrees,CharacterAutonomy.MotionAngle(Quaternion.identity,delta));
            }
            applied=true;
            // One visible-pose notification plus completion, not per-frame JSON.
            if(!reportedPose && elapsed>=.75f) {reportedPose=true;OnChanged?.Invoke();}
        }
        public void RestorePose()
        {
            if(!applied || !rig)return;
            for(int i=0;i<rig.joints.Length;i++)if(rig.joints[i].bone)rig.joints[i].bone.localRotation=before[i];
            if(face!=null)for(int i=0;i<face.indices.Length;i++)if(face.skins[i])face.skins[i].SetBlendShapeWeight(face.indices[i],faceBefore[i]);
            applied=false;
        }
        public static float Duration(string gesture)=>gesture=="shy" || gesture=="sad"?4.4f:gesture=="curious" || gesture=="welcome"?4.1f:3.6f;
        public static float Smooth(float t) {t=Mathf.Clamp01(t);return t*t*t*(t*(t*6-15)+10);}
        static float Pulse(float t,float begin,float apex,float hold,float end)
            => t<begin || t>=end?0:t<apex?Smooth((t-begin)/(apex-begin)):t<hold?1:1-Smooth((t-hold)/(end-hold));

        // Choreography in the calibrated neutral character frame, degrees.
        // Small anticipation -> torso lead -> head/arm follow -> long settling.
        // Elbows lift forward/outward; hands never sweep across face or chest.
        public static Vector3 Sample(string gesture,string human,float seconds)
        {
            float t=seconds/Duration(gesture);
            float body=Pulse(t,.03f,.28f,.49f,.92f);
            float head=Pulse(t,.09f,.35f,.54f,.99f);
            float arm=Pulse(t,.12f,.4f,.56f,.95f);
            float anticipation=Pulse(t,0,.09f,.1f,.24f);
            float nod=Pulse(t,.12f,.3f,.31f,.51f)+.55f*Pulse(t,.46f,.6f,.61f,.86f);
            float sway=Pulse(t,.1f,.31f,.36f,.56f)-.65f*Pulse(t,.47f,.68f,.7f,.96f);
            float pitch=0,yaw=0,roll=0,chest=0,lean=0,open=0,elbow=0;
            switch(gesture) {
                case "agree":pitch=12*nod-2*anticipation;chest=2.2f*body;elbow=7*arm;break;
                case "happy":pitch=5*nod-3*head;roll=4*sway;chest=-2.5f*body;lean=1.4f*sway;open=10*arm;elbow=22*arm;break;
                case "curious":pitch=-3*head;roll=11*head-1.5f*anticipation;yaw=4*sway;chest=2*body;lean=2*body;elbow=11*arm;break;
                case "shy":pitch=13*head;yaw=7*sway;roll=-5*head;chest=4*body;lean=-1.5f*body;open=2*arm;elbow=15*arm;break;
                case "pout":pitch=-3*head;yaw=12*sway;roll=3*head;chest=-2*body;lean=-1.8f*sway;open=5*arm;elbow=18*arm;break;
                case "sad":pitch=12*head;roll=5*head;chest=4.5f*body;lean=1.2f*body;elbow=5*arm;break;
                case "surprised":pitch=-9*head-1*anticipation;chest=-3.2f*body;open=9*arm;elbow=26*arm;break;
                case "welcome":pitch=6*nod;roll=3*sway;chest=-1.5f*body;open=14*arm;elbow=38*arm;break;
                case "encourage":pitch=9*nod;roll=-3*head;chest=-2*body;open=8*arm;elbow=31*arm;break;
                case "disagree":pitch=2*head;yaw=17*sway;chest=2*body;open=4*arm;elbow=12*arm;break;
            }
            bool left=human.StartsWith("Left",StringComparison.Ordinal);float side=left?1:-1;
            switch(human) {
                case "Spine":return new Vector3(chest*.35f,0,lean*.35f);
                case "Chest":return new Vector3(chest*.65f,0,lean*.65f);
                case "Neck":return new Vector3(pitch*.3f,yaw*.3f,roll*.3f);
                case "Head":return new Vector3(pitch*.7f,yaw*.7f,roll*.7f);
                case "LeftShoulder":case "RightShoulder":return new Vector3(0,0,side*open*.2f);
                case "LeftUpperArm":case "RightUpperArm":return new Vector3(-elbow*.14f,0,side*open*(gesture=="welcome" || gesture=="encourage"?(left?.32f:1):1));
                case "LeftLowerArm":case "RightLowerArm":return new Vector3(-elbow*(gesture=="welcome" || gesture=="encourage"?(left?.25f:1):(left?1:.82f)),0,0);
                case "LeftHand":case "RightHand":return new Vector3(0,gesture=="welcome" && !left?7*sway:0,gesture=="welcome" && !left?6*sway:0);
                default:return Vector3.zero;
            }
        }
    }
}
