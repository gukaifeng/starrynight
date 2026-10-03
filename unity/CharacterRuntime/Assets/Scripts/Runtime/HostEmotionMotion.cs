using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class HostEmotionMotionState
    {
        public int revision=3,started,completed,gestureCount=48;
        public bool supported,enabled,suppressed,speechLinked,speaking,automatic;
        public string gesture="",expression="",origin="starrynight.host-emotion.v3.experiment";
        public EmotionMapping[] standardMappings=Array.Empty<EmotionMapping>();
        public string standardEmotion="",standardStyle="plain",standardVocal="",standardStyleVariant="";
        public string[] expressions=Array.Empty<string>();
        public float weight,progress,peakDegrees;
    }

    // Optional, masked additive upper-body animation AFTER author animation and
    // gaze, BEFORE cloth/hair. Calibrated facial morphs are also overlaid, but
    // never speech visemes. Standard variants use calibrated fingers; the natural
    // body layer supplies contact-preserving hips/knees/feet. No presentation root writes.
    // All offsets unwind before the next animation sample; cancellation also has
    // an explicit C2 release, so turning the experiment off never pops the pose.
    [DefaultExecutionOrder(90)]
    public sealed class HostEmotionMotion : MonoBehaviour
    {
        public static string[] Gestures=>Array.ConvertAll(HostEmotionGestureLibrary.Catalog.gestures,p=>p.id);
        // Serialized v2 packages already contain these calibrated author faces.
        // New choreography reuses them, so old OSS packages need no rebuild.
        public static readonly string[] FacialGestures={"agree","happy","curious","shy","pout","sad","surprised","welcome","encourage","disagree"};
        public HostEmotionMotionState State {get;private set;}=new HostEmotionMotionState();
        public Action OnChanged;
        HostEmotionRig rig;
        ViewerCharacter character;
        CharacterActions actions;
        AvatarControlDriver author;
        HostEmotionRig.Joint[] joints=Array.Empty<HostEmotionRig.Joint>();
        Quaternion[] before=Array.Empty<Quaternion>();
        HostEmotionRig.Face face,secondaryFace;
        HostEmotionGesture profile,accentProfile;
        HostEmotionRig.Face accentFace;
        float[] accentBefore=Array.Empty<float>();
        float accentElapsed,standardDuration;
        float[] faceBefore=Array.Empty<float>();
        float[] secondaryBefore=Array.Empty<float>();
        struct Guard {public int hash;public string kind;public float initial;}
        Guard[] guards=Array.Empty<Guard>();
        bool applied,interacting,reportedPose,accentApplied;
        string queued="",speechIntent="neutral",lastAutomatic="";
        bool queuedAutomatic;
        string lastStandardBase="",standardStyleVariant="";
        readonly Dictionary<string,string> lastStandardKinds=new Dictionary<string,string>();
        public float StanceAccent=>profile?.stance ?? 0;
        public float GestureEnvelope=>profile!=null?Pulse(State.progress,.025f,.27f,.5f,.94f)*State.weight:0;
        int speechSequence;
        float elapsed,gap,intensity=1,release=-1,releaseStart=1,speechStartDelay;
        public void Bind(ViewerCharacter actor,CharacterActions source)
        {
            Clear();character=actor;actions=source;rig=actor.GetComponent<HostEmotionRig>();
            author=actor.GetComponent<AvatarControlDriver>();
            State=new HostEmotionMotionState {supported=rig && rig.joints.Length>=10,gestureCount=Gestures.Length,
                expressions=rig?Array.ConvertAll(rig.faces,f=>f.gesture+" · "+f.label):Array.Empty<string>()};
            joints=rig?rig.joints.Concat(rig.naturalJoints??Array.Empty<HostEmotionRig.Joint>()).Where(j=>!j.human.Contains("Leg") && !j.human.EndsWith("Foot") && j.human!="Hips").GroupBy(j=>j.human).Select(g=>g.First()).ToArray():Array.Empty<HostEmotionRig.Joint>();
            before=new Quaternion[joints.Length];

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
            face=secondaryFace=accentFace=null;profile=accentProfile=null;accentElapsed=standardDuration=0;faceBefore=secondaryBefore=Array.Empty<float>();
            speechIntent="neutral";lastAutomatic="";lastStandardKinds.Clear();lastStandardBase=standardStyleVariant="";joints=Array.Empty<HostEmotionRig.Joint>();speechSequence=0;queuedAutomatic=false;speechStartDelay=0;
        }
        public void Configure(bool value)
        {
            State.enabled=value && State.supported;
            if(!State.enabled)Cancel();
        }
        public void SetInteracting(bool value) {interacting=value;}
        public void ConfigureSpeech(bool value)
        {
            State.speechLinked=value;
            if(!value && State.automatic)Cancel();
            if(value && State.enabled && State.speaking)speechStartDelay=.12f;
        }
        public void SetSpeech(bool value)
        {
            bool entering=value && !State.speaking;State.speaking=value;
            if(!value){if(State.automatic)Cancel();speechIntent="neutral";speechStartDelay=0;}
            // The native beat callback schedules expression tasks just before
            // the speaking event. Allow a few frames for those existing tasks;
            // audio itself is never delayed or awaited by this layer.
            if(entering && State.enabled && State.speechLinked)speechStartDelay=.12f;
        }
        public string CueIntent(string intent)
        {
            speechIntent=HostEmotionGestureLibrary.Normalize(intent);
            if(!State.speechLinked)return "HOST_MOTION_DEVELOPER_ONLY";
            if(State.gesture.Contains("."))return null;
            if(!State.speaking)return null; // Beat cues can arrive just before audio begins.
            if(speechStartDelay>0)return null;
            if(State.gesture.Length>0 && (!State.automatic || elapsed<1.5f))return null;
            string chosen=HostEmotionGestureLibrary.Select(speechIntent,++speechSequence,lastAutomatic);
            if(chosen.Length==0)return "HOST_MOTION_UNKNOWN_INTENT";
            return Request(chosen,false);
        }
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
            if(!State.speechLinked)return "HOST_MOTION_DEVELOPER_ONLY";
            var choices=character?.Manifest?.performance?.options;
            if(choices==null)return null;
            var choice=Array.Find(choices,o=>o.id==option);
            if(choice?.ai==null || !choice.ai.automatic || choice.ai.kind!="expression")return null;
            return CueIntent(choice.ai.intent);
        }
        public string Request(string gesture,bool preview)
        {
            if(!State.supported)return "HOST_MOTION_UNSUPPORTED";
            if(!State.enabled)return "HOST_MOTION_DISABLED";
            if(!preview && (!State.speechLinked || !State.speaking))return "HOST_MOTION_DEVELOPER_ONLY";
            if(HostEmotionGestureLibrary.Find(gesture)==null)return "HOST_MOTION_UNKNOWN";
            if(Blocked())return "HOST_MOTION_AUTHOR_PRIORITY";
            if(State.gesture.Length>0 || gap>0) {
                // A bounded latest-only queue; speech can never build a backlog.
                if(gesture!=State.gesture || preview){queued=gesture;queuedAutomatic=!preview;}
                if(preview) {Cancel();queued=gesture;queuedAutomatic=false;}
                return null;
            }
            StartGesture(gesture,!preview);return null;
        }
        void StartGesture(string gesture,bool automatic=false)
        {
            State.gesture=gesture;elapsed=0;release=-1;State.weight=1;
            State.progress=State.peakDegrees=0;State.started++;reportedPose=false;
            profile=HostEmotionGestureLibrary.Find(gesture);State.automatic=automatic || (State.speaking && gesture.Contains("."));
            State.origin=gesture.Contains(".")?"starrynight.emotion-standard.v1":"starrynight.host-emotion.v3.experiment";
            if(automatic)lastAutomatic=gesture;
            var executed=EmotionPerformanceStandard.Variant(gesture);
            if(executed!=null) {lastStandardBase=executed.@base;lastStandardKinds[gesture.Split('.')[0]]=executed.@base;}
            face=EmotionPerformanceStandard.Face(rig,profile.expression);faceBefore=new float[face?.indices.Length ?? 0];
            secondaryFace=Array.Find(rig.faces,f=>f.gesture==profile.secondary);secondaryBefore=new float[secondaryFace?.indices.Length ?? 0];
            State.expression=face?.label ?? "中性表情";
            if(secondaryFace!=null)State.expression+=" → "+secondaryFace.label;
            if(State.gesture.StartsWith("emotion.") && standardStyleVariant.Length>0) {
                var style=EmotionPerformanceStandard.Gesture(standardStyleVariant);
                if(style!=null) {
                    for(int i=0;i<profile.c.Length;i++)profile.c[i]=Mathf.Lerp(profile.c[i],style.c[i],.25f);
                    lastStandardKinds["style"]=EmotionPerformanceStandard.Variant(standardStyleVariant).@base;
                }
            }
            if(gesture.Contains(".") && standardDuration>0)profile.duration=Mathf.Clamp(standardDuration,1.2f,6.5f);
            // Stable alternation keeps a replay auditable, without frame-dependent noise.
            intensity=(State.started%2==0?.94f:1)*rig.amplitude;
        }
        public string PreviewStandard(string id) {
            var v=EmotionPerformanceStandard.Variant(id);if(v==null)return "EMOTION_STANDARD_UNKNOWN";
            RestorePose();accentProfile=null;accentFace=null;standardStyleVariant="";standardDuration=0;
            var error=Request(id,true);State.automatic=false;
            if(error==null) {
                var entry=EmotionPerformanceStandard.Entry(id.Split('.')[0],id.Split('.')[1]);
                var player=GetComponent<CharacterPerformanceDriver>();
                if(player)foreach(var option in EmotionPerformanceStandard.Original(character,entry))player.Select(option.id,.65f);
            }
            return error;
        }
        public void PublishMappings() {
            if(!rig || !character)return;
            State.standardMappings=EmotionPerformanceStandard.Map(character,rig);
            OnChanged?.Invoke();State.standardMappings=Array.Empty<EmotionMapping>();
        }
        public string Standard(string kind,string id,string style="plain",bool preview=false,float duration=0) {
            var entry=EmotionPerformanceStandard.Entry(kind,id);if(entry==null)return "EMOTION_STANDARD_UNKNOWN";
            if(!State.supported)return "HOST_MOTION_UNSUPPORTED";
            if(!State.enabled)return "HOST_MOTION_DISABLED";
            if(Blocked())return "HOST_MOTION_AUTHOR_PRIORITY";
            if(kind=="emotion") {State.standardEmotion=id;State.standardStyle=style;State.standardVocal="";
                standardStyleVariant=EmotionPerformanceStandard.Entry("style",style)==null?"":EmotionPerformanceStandard.Choose("style",style,lastStandardBase,lastStandardKinds.TryGetValue("style",out var priorStyle)?priorStyle:"");
                State.standardStyleVariant=standardStyleVariant;}
            if(kind=="vocal")State.standardVocal=id;
            if(kind=="emotion")standardDuration=!preview?duration:0;
            var chosen=EmotionPerformanceStandard.Choose(kind,id,lastStandardBase,lastStandardKinds.TryGetValue(kind,out var priorKind)?priorKind:"");
            if(kind=="vocal" && !preview && State.gesture.Length>0) {
                lastStandardBase=EmotionPerformanceStandard.Variant(chosen).@base;lastStandardKinds[kind]=lastStandardBase;
                RestorePose();
                accentProfile=EmotionPerformanceStandard.Gesture(chosen);accentElapsed=0;
                accentFace=EmotionPerformanceStandard.Face(rig,accentProfile.expression);accentBefore=new float[accentFace?.indices.Length??0];
                OnChanged?.Invoke();return null;
            }
            var error=Request(chosen,true);
            if(!preview){State.automatic=true;queuedAutomatic=false;}
            var player=GetComponent<CharacterPerformanceDriver>();
            if(player && error==null && !Blocked())foreach(var option in EmotionPerformanceStandard.Original(character,entry))player.Select(option.id,.65f);
            OnChanged?.Invoke();return error;
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
            if(speechStartDelay>0) {
                speechStartDelay=Mathf.Max(0,speechStartDelay-dt);
                if(speechStartDelay==0 && State.enabled && State.speechLinked && State.speaking && !State.suppressed)
                    CueIntent(speechIntent);
            }
            gap=Mathf.Max(0,gap-dt);
            if(State.gesture.Length==0) {
                if(State.enabled && !State.suppressed && gap==0 && queued.Length>0) {
                    var next=queued;bool automatic=queuedAutomatic;queued="";
                    if(!automatic || (State.speechLinked && State.speaking))StartGesture(next,automatic);
                    else return;
                } else return;
            }
            elapsed+=dt;
            float duration=profile?.duration ?? Duration(State.gesture);State.progress=Mathf.Clamp01(elapsed/duration);
            if(release>=0) {release+=dt;State.weight=releaseStart*(1-Smooth(release/.48f));}
            if(elapsed>=duration || (release>=.48f)) {
                State.completed++;State.gesture=State.expression="";State.weight=0;State.progress=1;gap=.24f;release=-1;OnChanged?.Invoke();return;
            }
            float transition=secondaryFace!=null?Smooth((elapsed/duration-.37f)/.26f):0;
            if(face!=null){
                float faceWeight=Pulse(elapsed/duration,.04f,.3f,.62f,1)*State.weight*profile.face*(1-transition);
                for(int i=0;i<face.indices.Length;i++){var skin=face.skins[i];faceBefore[i]=skin.GetBlendShapeWeight(face.indices[i]);skin.SetBlendShapeWeight(face.indices[i],Mathf.Lerp(faceBefore[i],face.values[i],faceWeight));}
            }
            if(secondaryFace!=null){
                float faceWeight=Pulse(elapsed/duration,.04f,.3f,.62f,1)*State.weight*profile.face*transition;
                for(int i=0;i<secondaryFace.indices.Length;i++){var skin=secondaryFace.skins[i];secondaryBefore[i]=skin.GetBlendShapeWeight(secondaryFace.indices[i]);skin.SetBlendShapeWeight(secondaryFace.indices[i],Mathf.Lerp(secondaryBefore[i],secondaryFace.values[i],faceWeight));}
            }
            float accent=0;
            if(accentProfile!=null) {
                accentElapsed+=dt;accent=Pulse(accentElapsed/1.25f,0,.2f,.55f,1)*State.weight;
                if(accentFace!=null)for(int i=0;i<accentFace.indices.Length;i++) {
                    var skin=accentFace.skins[i];accentBefore[i]=skin.GetBlendShapeWeight(accentFace.indices[i]);
                    skin.SetBlendShapeWeight(accentFace.indices[i],Mathf.Lerp(accentBefore[i],accentFace.values[i],accent*.32f));accentApplied=true;
                }
            }
            for(int i=0;i<joints.Length;i++) {
                var j=joints[i];before[i]=j.bone.localRotation;
                var euler=Sample(profile,j.human,elapsed)*intensity*State.weight;
                if(accentProfile!=null)euler+=Sample(accentProfile,j.human,accentProfile.duration*.43f)*accent*.16f;
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
            for(int i=0;i<joints.Length;i++)if(joints[i].bone)joints[i].bone.localRotation=before[i];
            if(accentApplied && accentFace!=null)for(int i=0;i<accentFace.indices.Length;i++)if(accentFace.skins[i])accentFace.skins[i].SetBlendShapeWeight(accentFace.indices[i],accentBefore[i]);
            accentApplied=false;
            if(accentProfile!=null && accentElapsed>=1.25f){accentProfile=null;accentFace=null;}
            // Reverse order matters when two authored faces share morph channels.
            if(secondaryFace!=null)for(int i=0;i<secondaryFace.indices.Length;i++)if(secondaryFace.skins[i])secondaryFace.skins[i].SetBlendShapeWeight(secondaryFace.indices[i],secondaryBefore[i]);
            if(face!=null)for(int i=0;i<face.indices.Length;i++)if(face.skins[i])face.skins[i].SetBlendShapeWeight(face.indices[i],faceBefore[i]);
            applied=false;
        }
        public static float Duration(string gesture)=>HostEmotionGestureLibrary.Find(gesture)?.duration ?? 4.5f;
        public static float Smooth(float t) {t=Mathf.Clamp01(t);return t*t*t*(t*(t*6-15)+10);}
        static float Pulse(float t,float begin,float apex,float hold,float end)
            => t<begin || t>=end?0:t<apex?Smooth((t-begin)/(apex-begin)):t<hold?1:1-Smooth((t-hold)/(end-hold));

        // Host-authored choreography, NOT motion capture. Each profile has
        // anatomical amplitudes, distinct asymmetry and rhythmic accents.
        // Forward/outward elbows keep hands away from face/chest; never IK reach.
        public static Vector3 Sample(string gesture,string human,float seconds)
            =>Sample(HostEmotionGestureLibrary.Find(gesture),human,seconds);
        static Vector3 Sample(HostEmotionGesture p,string human,float seconds)
        {
            if(p==null)return Vector3.zero;
            float t=seconds/p.duration;
            float body=Pulse(t,.025f,.27f,.5f,.94f);
            float head=Pulse(t,.085f,.34f,.57f,1);
            float arm=Pulse(t,.13f,.4f,.59f,.98f);
            float anticipation=Pulse(t,0,.09f,.1f,.24f);
            float nod=Pulse(t,.13f,.3f,.31f,.51f);
            if(p.beats>=2)nod+=.65f*Pulse(t,.47f,.6f,.61f,.85f);
            if(p.beats>=3)nod+=.35f*Pulse(t,.71f,.79f,.8f,.95f);
            float sway=Pulse(t,.12f,.3f,.34f,.55f)-.7f*Pulse(t,.49f,.68f,.72f,.97f);
            float pitch=Mathf.Clamp(p.c[0]*head+p.nod*nod-1.7f*anticipation,-18,24);
            float yaw=Mathf.Clamp(p.c[1]*head+p.shake*sway,-26,26);
            float roll=Mathf.Clamp(p.c[2]*head-p.c[2]*.12f*anticipation,-17,17);
            float chest=p.c[3]*body,lean=p.c[4]*body,twist=p.c[5]*body;
            bool left=human.StartsWith("Left",StringComparison.Ordinal);float side=left?1:-1;
            float open=p.c[left?6:7]*arm;
            float forward=p.c[left?8:9]*arm;
            float elbow=p.c[left?10:11]*arm;
            float wrist=p.c[12]*arm;
            float wave=p.wave*sway;
            // The wave lives in the raised RIGHT forearm/wrist; no high speed
            // sine noise. Nods/accents share C2 envelopes and a long release.
            if(!left){elbow+=4*wave;open+=3*wave;}
            switch(human) {
                case "Spine":return new Vector3(chest*.35f,twist*.4f,lean*.35f);
                case "Chest":return new Vector3(chest*.65f,twist*.6f,lean*.65f);
                case "Neck":return new Vector3(pitch*.3f,yaw*.3f,roll*.3f);
                case "Head":return new Vector3(pitch*.7f,yaw*.7f,roll*.7f);
                case "LeftShoulder":case "RightShoulder":return new Vector3(-forward*.14f,0,side*open*.16f);
                case "LeftUpperArm":case "RightUpperArm":return new Vector3(-forward,0,side*open);
                case "LeftLowerArm":case "RightLowerArm":return new Vector3(-Mathf.Clamp(elbow,0,72),0,0);
                case "LeftHand":case "RightHand":return new Vector3(0,side*wrist*.5f,side*wrist*.35f+(!left?12*wave:0));
                default:return human.EndsWith("Proximal",StringComparison.Ordinal)?new Vector3(p.finger*arm,0,(left?1:-1)*p.finger*.25f*sway):Vector3.zero;
            }
        }
    }
}
