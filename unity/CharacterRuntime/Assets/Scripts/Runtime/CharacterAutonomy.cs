using System;
using System.Linq;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class CharacterBlinkProfile
    {
        public ShapeBinding[] bindings=Array.Empty<ShapeBinding>();
        // Repeated entries represent the author's weighted interval lottery.
        public float[] intervals=Array.Empty<float>();
        public float closeSeconds=.09f,closedSeconds=.02f,openSeconds=.13f,firstDelay=2;
        public string[] suppressGroups=Array.Empty<string>(),suppressOptions=Array.Empty<string>();
    }
    [Serializable] public sealed class CharacterBreathingProfile
    {
        public string clip;
        public string[] bones=Array.Empty<string>(),poseOptions=Array.Empty<string>();
    }
    [Serializable] public sealed class CharacterAutonomyProfile
    {
        public int schemaVersion=1;
        public CharacterBlinkProfile blink;
        public CharacterBreathingProfile breathing;
    }
    [Serializable] public sealed class CharacterAutonomyState
    {
        public int revision=2,blinkCount;
        public bool enabled,blinkSuppressed;
        public float blinkWeight,blinkDurationSeconds,poseBreathWeight,headMotionDegrees,chestMotionDegrees;
        public float hairTravel,clothTravel;
        public int windStrands;
    }
    public static class CharacterAutonomyContract
    {
        public static bool Supported(CharacterManifest m) => m.Supports("core.autonomy@1") && m.autonomy?.blink?.bindings?.Length>0;
        static bool Range(float x,float min,float max)=>float.IsFinite(x) && x>=min && x<=max;
        public static void Validate(CharacterManifest m)
        {
            var p=m.autonomy;
            if(!m.Supports("core.autonomy@1"))return;
            if(p==null || p.schemaVersion!=1 || p.blink==null)throw new ArgumentException("AUTONOMY_SCHEMA_INVALID");
            var b=p.blink;
            if(b.bindings==null || b.bindings.Length<1 || b.bindings.Length>4 ||
                b.bindings.Any(s=>s==null || string.IsNullOrEmpty(s.renderer) || string.IsNullOrEmpty(s.shape) || !Range(s.weight,0,1)) ||
                b.bindings.Select(s=>s.renderer+"\n"+s.shape).Distinct().Count()!=b.bindings.Length ||
                b.intervals==null || b.intervals.Length<1 || b.intervals.Length>16 || b.intervals.Any(t=>!Range(t,.2f,30)) ||
                !Range(b.closeSeconds,.04f,.3f) || !Range(b.closedSeconds,0,.1f) || !Range(b.openSeconds,.04f,.4f) || !Range(b.firstDelay,.2f,10))
                throw new ArgumentException("AUTONOMY_BLINK_INVALID");
            var options=m.performance?.options ?? Array.Empty<CharacterPerformanceOption>();
            if(b.suppressGroups==null || b.suppressOptions==null || b.suppressGroups.Length>6 || b.suppressOptions.Length>256 ||
                b.suppressGroups.Any(g=>!CharacterPerformanceContract.Groups.Contains(g)) || b.suppressOptions.Any(id=>!options.Any(o=>o.id==id)))
                throw new ArgumentException("AUTONOMY_PRIORITY_INVALID");
            var r=p.breathing;
            if(r!=null && !string.IsNullOrEmpty(r.clip) && (r.bones==null || r.bones.Length<1 || r.bones.Length>16 ||
                r.bones.Any(string.IsNullOrEmpty) || r.poseOptions==null || r.poseOptions.Length>64 ||
                r.poseOptions.Any(id=>!options.Any(o=>o.id==id && o.group=="pose" && !o.additive))))
                throw new ArgumentException("AUTONOMY_BREATH_INVALID");
        }
    }

    // This outer facial layer restores before performance (35), expressions (55),
    // and the next animation sample. It never modifies a mouth, root or camera.
    [DefaultExecutionOrder(65)]
    public sealed class CharacterAutonomy : MonoBehaviour
    {
        const string BreathAlias="__autonomy_source_breath";
        sealed class Lid { public SkinnedMeshRenderer skin; public int index; public float scale,weight,baseline; }
        Lid[] lids=Array.Empty<Lid>();
        CharacterAutonomyProfile profile;
        CharacterPerformanceDriver performance;
        ViewerCharacter character;
        Animation player; AnimationState breath;
        AvatarSecondaryMotion secondary;
        System.Random random;
        float untilBlink,blinkTime=-1;
        bool applied;
        Transform head,chest;
        Quaternion previousHead,previousChest;
        bool sampled;
        public CharacterAutonomyState State { get; private set; }=new CharacterAutonomyState();
        public void Bind(ViewerCharacter c,CharacterPerformanceDriver overlay,int seed=0)
        {
            Clear();character=c;performance=overlay;
            State=new CharacterAutonomyState {enabled=CharacterAutonomyContract.Supported(c.Manifest)};
            if(!State.enabled)return;
            profile=c.Manifest.autonomy;random=new System.Random(seed==0?Environment.TickCount:seed);
            State.blinkDurationSeconds=profile.blink.closeSeconds+profile.blink.closedSeconds+profile.blink.openSeconds;
            var restore=GetComponent<CharacterAutonomyRestore>() ?? gameObject.AddComponent<CharacterAutonomyRestore>();restore.driver=this;
            lids=profile.blink.bindings.Select(b=>{
                var skin=CharacterContract.Resolve(c.transform,b.renderer)?.GetComponent<SkinnedMeshRenderer>();
                int index=skin?skin.sharedMesh.GetBlendShapeIndex(b.shape):-1;
                if(index<0)throw new ArgumentException("AUTONOMY_LID_MISSING: "+b.shape);
                return new Lid {skin=skin,index=index,scale=CharacterContract.MorphScale(skin,index),weight=b.weight};
            }).ToArray();
            untilBlink=profile.blink.firstDelay;
            head=CharacterContract.Resolve(c.transform,c.Manifest.rig.head);
            chest=CharacterContract.Resolve(c.transform,c.Manifest.rig.neck)?.parent;
            player=c.GetComponent<Animation>();
            secondary=c.GetComponent<AvatarSecondaryMotion>();
            var r=profile.breathing;
            if(r!=null && !string.IsNullOrEmpty(r.clip))
            {
                var clip=player?player.GetClip(r.clip):null;
                if(!clip)throw new ArgumentException("AUTONOMY_BREATH_MISSING: "+r.clip);
                player.AddClip(clip,BreathAlias);breath=player[BreathAlias];
                breath.layer=30;breath.blendMode=AnimationBlendMode.Additive;breath.wrapMode=WrapMode.Loop;
                foreach(string path in r.bones)breath.AddMixingTransform(CharacterContract.Resolve(c.transform,path),false);
                breath.enabled=false;breath.weight=0;
            }
        }
        public void Clear()
        {
            RestoreMorphs();if(breath!=null){breath.enabled=false;breath.weight=0;}
            if(player && player.GetClip(BreathAlias))player.RemoveClip(BreathAlias);
            lids=Array.Empty<Lid>();profile=null;breath=null;player=null;character=null;sampled=false;blinkTime=-1;
            State=new CharacterAutonomyState();
        }
        void OnDisable(){RestoreMorphs();if(breath!=null){breath.enabled=false;breath.weight=0;}}
        void OnApplicationPause(bool paused)
        {
            RestoreMorphs();blinkTime=-1;State.blinkWeight=0;sampled=false;
            if(profile!=null)untilBlink=profile.blink.firstDelay;
        }
        void Update(){Step(Time.deltaTime);}
        public void Step(float dt)
        {
            if(!State.enabled || !character || !character.gameObject.activeInHierarchy || dt<=0)return;
            if(dt>.15f){blinkTime=-1;untilBlink=profile.blink.firstDelay;State.blinkWeight=0;sampled=false;}
            dt=Mathf.Min(dt,1f/30);
            if(breath!=null)
            {
                // The neutral Idle already includes source breath. Only add it to
                // static poses that replace that layer, synchronized to its phase.
                float weight=performance?performance.WeightFor(null,profile.breathing.poseOptions):0;
                breath.weight=weight;breath.enabled=weight>.0001f;
                breath.time=player["Idle"].time%breath.length;State.poseBreathWeight=weight;
            }
            float suppression=performance?performance.WeightFor(profile.blink.suppressGroups,profile.blink.suppressOptions):0;
            var authored=character.GetComponent<AvatarControlDriver>();
            State.blinkSuppressed=suppression>.0001f || (authored && !authored.AllowBlink);
            if(State.blinkSuppressed)
            {
                blinkTime=-1;untilBlink=profile.blink.firstDelay;
                State.blinkWeight=Mathf.MoveTowards(State.blinkWeight,0,dt/.06f);return;
            }
            if(blinkTime<0)
            {
                untilBlink-=dt;
                if(untilBlink<=0){blinkTime=-untilBlink;State.blinkCount++;}
            }
            else blinkTime+=dt;
            var b=profile.blink;
            if(blinkTime>=b.closeSeconds+b.closedSeconds+b.openSeconds)
            {blinkTime=-1;untilBlink=b.intervals[random.Next(b.intervals.Length)];}
            State.blinkWeight=blinkTime<0?0:Closure(blinkTime,b);
        }
        public static float Closure(float t,CharacterBlinkProfile b)
        {
            if(t<0)return 0;
            if(t<b.closeSeconds)return Smooth(t/b.closeSeconds);
            if(t<b.closeSeconds+b.closedSeconds)return 1;
            return 1-Smooth((t-b.closeSeconds-b.closedSeconds)/b.openSeconds);
        }
        static float Smooth(float t){t=Mathf.Clamp01(t);return t*t*t*(t*(t*6-15)+10);}
        // Quaternion.Angle rounds very small per-frame breath rotations to zero.
        public static float MotionAngle(Quaternion a,Quaternion b)
        {
            var q=Quaternion.Inverse(a)*b;
            return 2*Mathf.Atan2(new Vector3(q.x,q.y,q.z).magnitude,Mathf.Abs(q.w))*Mathf.Rad2Deg;
        }
        void LateUpdate(){ApplyFrame();}
        public void ApplyFrame()
        {
            if(!State.enabled || !character || !character.gameObject.activeInHierarchy)return;
            foreach(var lid in lids)
            {
                lid.baseline=lid.skin.GetBlendShapeWeight(lid.index);
                // Never reopen an authored closed eye. Positive eye expressions
                // own their channels, with suppression including their fade-out.
                lid.skin.SetBlendShapeWeight(lid.index,Mathf.Lerp(lid.baseline,Mathf.Max(lid.baseline,lid.scale*lid.weight),State.blinkWeight));
            }
            applied=true;
            if(sampled)
            {
                if(head)State.headMotionDegrees+=MotionAngle(previousHead,head.localRotation);
                if(chest)State.chestMotionDegrees+=MotionAngle(previousChest,chest.localRotation);
            }
            if(head)previousHead=head.localRotation;if(chest)previousChest=chest.localRotation;sampled=true;
            if(secondary){State.hairTravel=secondary.HairTravel;State.clothTravel=secondary.ClothTravel;State.windStrands=secondary.WindStrands;}
        }
        public void RestoreMorphs()
        {
            if(!applied)return;
            foreach(var lid in lids)if(lid.skin)lid.skin.SetBlendShapeWeight(lid.index,lid.baseline);
            applied=false;
        }
    }
}
