using System;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class PostureParameter
    {
        public string id,label,unit="normalized",lowClip,highClip;
        public float min,max=1,initial=.5f;
    }
    [Serializable] public sealed class PostureAction { public string action,clip; }
    [Serializable] public sealed class PostureDefinition
    {
        public string id,label,clip,symbol="figure.stand",support="floor",gaze="follow";
        public float transition=1.2f;
        public PostureParameter[] parameters=Array.Empty<PostureParameter>();
        public PostureAction[] actions=Array.Empty<PostureAction>();
    }
    [Serializable] public sealed class PostureProfile
    {
        public string[] bones=Array.Empty<string>();
        public PostureDefinition[] poses=Array.Empty<PostureDefinition>();
        public IEnumerable<string> Clips => poses.SelectMany(p=>new[]{p.clip}.Concat(p.parameters.SelectMany(v=>new[]{v.lowClip,v.highClip})).Concat(p.actions.Select(a=>a.clip))).Distinct();
    }
    [Serializable] public sealed class PostureRequest
    {
        public string id="stand";
        public CharacterParameterValue[] parameters=Array.Empty<CharacterParameterValue>();
    }
    [Serializable] public sealed class PostureState
    {
        public int revision=1;
        public string id="stand",support="floor",status="settled";
        public bool supported,transitioning;
        public float progress=1;
        public float groundLift;
        public CharacterParameterValue[] parameters=Array.Empty<CharacterParameterValue>();
    }
    // Author-owned clips, runtime-owned interpolation. No rig naming convention, downloaded code,
    // runtime mesh bake or per-frame IK. Animation -> posture (40) -> speech (50) -> gaze (80).
    [DefaultExecutionOrder(40)]
    public sealed class CharacterPosture : MonoBehaviour
    {
        struct Frame { public Vector3 p; public Quaternion q; }
        ViewerCharacter character; CharacterActions actions; Animation player;
        PostureGrounding grounding;
        Transform[] bones=Array.Empty<Transform>();
        readonly Dictionary<string,Frame[]> frames=new Dictionary<string,Frame[]>();
        Frame[] origin,restored;
        float[] values,velocities;
        float elapsed,duration;
        bool applied,notified;
        public PostureDefinition Definition { get; private set; }
        public PostureState State { get; private set; } = new PostureState();
        public Action OnChanged,OnSettled;
        Frame[] Capture() => bones.Select(t=>new Frame { p=t.localPosition,q=t.localRotation }).ToArray();
        void Write(Frame[] f) { for(int i=0;i<bones.Length;i++) { bones[i].localPosition=f[i].p; bones[i].localRotation=f[i].q; } }
        public void Bind(ViewerCharacter c,CharacterActions source)
        {
            Restore(); character=c; actions=source; frames.Clear(); Definition=null; bones=Array.Empty<Transform>();grounding=c.GetComponent<PostureGrounding>();
            actions.Posture=this;
            State=new PostureState { supported=c.Manifest.posture!=null && c.Manifest.posture.poses.Length>0 };
            if(!State.supported) return;
            player=c.GetComponentInChildren<Animation>(true);
            bones=c.Manifest.posture.bones.Select(p=>CharacterContract.Resolve(c.transform,p)).ToArray();
            var original=Capture();
            foreach(string clip in c.Manifest.posture.Clips)
            {
                Write(original); player.GetClip(clip).SampleAnimation(c.gameObject,0); frames[clip]=Capture();
            }
            Write(original); player.GetClip("Idle").SampleAnimation(c.gameObject,0);
            origin=Capture(); restored=Capture();
            Definition=c.Manifest.posture.poses.First(p=>p.id=="stand");
            values=Definition.parameters.Select(p=>p.initial).ToArray();velocities=new float[values.Length];
            State.parameters=Definition.parameters.Select(p=>new CharacterParameterValue {id=p.id,value=p.initial}).ToArray();
            duration=elapsed=0;notified=true;
        }
        public string Validate(PostureRequest request)
        {
            if(request==null || string.IsNullOrEmpty(request.id)) return "POSTURE_INVALID";
            if(!State.supported) return request.id=="stand" && (request.parameters==null || request.parameters.Length==0) ? null : "POSTURE_UNSUPPORTED";
            var pose=Array.Find(character.Manifest.posture.poses,p=>p.id==request.id);
            if(pose==null) return "POSTURE_UNAVAILABLE";
            if(pose.support!="floor") return "POSTURE_SUPPORT_UNAVAILABLE";
            var supplied=request.parameters ?? Array.Empty<CharacterParameterValue>();
            if(supplied.Length>12 || supplied.Any(p=>p==null || string.IsNullOrEmpty(p.id)) || supplied.Select(p=>p.id).Distinct().Count()!=supplied.Length) return "POSTURE_PARAMETER_INVALID";
            foreach(var value in supplied)
            {
                var parameter=Array.Find(pose.parameters,p=>p.id==value.id);
                if(parameter==null) return "POSTURE_PARAMETER_UNKNOWN";
                if(float.IsNaN(value.value) || float.IsInfinity(value.value) || value.value<parameter.min || value.value>parameter.max) return "POSTURE_PARAMETER_RANGE";
            }
            return null;
        }
        public void Configure(PostureRequest request)
        {
            var error=Validate(request);if(error!=null) throw new ArgumentException(error);
            if(!State.supported) return;
            var next=Array.Find(character.Manifest.posture.poses,p=>p.id==request.id);
            var target=next.parameters.Select(p=>new CharacterParameterValue { id=p.id,value=Array.Find(request.parameters ?? Array.Empty<CharacterParameterValue>(),v=>v.id==p.id)?.value ?? p.initial }).ToArray();
            if(State.id==request.id && target.Length==State.parameters.Length && target.Select((v,i)=>Mathf.Abs(v.value-State.parameters[i].value)<.00001f).All(x=>x)) return;
            if(next!=Definition)
            {
                origin=Capture(); elapsed=0;duration=next.transition;
                Definition=next;State.id=next.id;State.support=next.support;
                values=next.parameters.Select(p=>p.initial).ToArray();velocities=new float[values.Length];
                actions.SetRestClip(next.clip);
            }
            State.parameters=target;State.transitioning=true;State.status="transitioning";notified=false;
            OnChanged?.Invoke();
        }
        public string ActionClip(string action)
        {
            if(!State.supported) return action;
            return Array.Find(Definition.actions,a=>a.action==action)?.clip;
        }
        public string FramingClip => State.supported ? Definition.clip : "Idle";
        public void Restore() { if(grounding)grounding.Restore();if(applied && restored!=null) Write(restored);applied=false; }
        void Update() { Restore(); }
        void OnDisable() { Restore(); }
        void LateUpdate() { Step(Time.unscaledDeltaTime); }
        public void Step(float dt)
        {
            if(!State.supported || !character.gameObject.activeInHierarchy) return;
            dt=Mathf.Clamp(dt,0,.05f);elapsed+=dt;
            float t=duration<=0?1:Mathf.Clamp01(elapsed/duration);
            float eased=t*t*t*(t*(t*6-15)+10); // C2 endpoint continuity, no angular overshoot.
            bool moving=t<1;
            for(int p=0;p<values.Length;p++)
            {
                values[p]=Mathf.SmoothDamp(values[p],State.parameters[p].value,ref velocities[p],.28f,Mathf.Infinity,dt);
                moving|=Mathf.Abs(values[p]-State.parameters[p].value)>.001f;
            }
            var basis=frames[Definition.clip];
            for(int b=0;b<bones.Length;b++)
            {
                var bone=bones[b];restored[b]=new Frame {p=bone.localPosition,q=bone.localRotation};
                var position=bone.localPosition;var rotation=bone.localRotation;
                for(int p=0;p<values.Length;p++)
                {
                    var parameter=Definition.parameters[p];float v=values[p];bool low=v<parameter.initial;
                    float span=low ? parameter.initial-parameter.min : parameter.max-parameter.initial;
                    float weight=span<.00001f?0:Mathf.Clamp01(Mathf.Abs(v-parameter.initial)/span);
                    var variant=frames[low ? parameter.lowClip : parameter.highClip][b];
                    position+=(variant.p-basis[b].p)*weight;
                    rotation*=Quaternion.Slerp(Quaternion.identity,Quaternion.Inverse(basis[b].q)*variant.q,weight);
                }
                bone.localPosition=Vector3.Lerp(origin[b].p,position,eased);
                bone.localRotation=Quaternion.Slerp(origin[b].q,rotation,eased);
            }
            applied=true;State.progress=t;State.transitioning=moving;State.status=moving?"transitioning":"settled";
            if(grounding){grounding.Apply();State.groundLift=grounding.Lift;}
            if(!moving && !notified) { notified=true;OnSettled?.Invoke(); }
        }
    }
}
