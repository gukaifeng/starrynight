using System;
using System.Collections;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class AvatarParameter { public string name,kind;public float initial;public bool saved; }
    [Serializable] public sealed class AvatarControl
    {
        public string id,label,group,parameter,kind;
        public float value,initial,minimum,maximum;
        public AvatarGate[] gates=Array.Empty<AvatarGate>();
    }
    [Serializable] public sealed class AvatarGate {public string parameter;public float value;}
    [Serializable] public sealed class AvatarControlProfile
    {
        public int schemaVersion=1;
        public AvatarParameter[] parameters=Array.Empty<AvatarParameter>();
        public AvatarControl[] controls=Array.Empty<AvatarControl>();
    }
    [Serializable] public sealed class AvatarLayerGroup { public int playable;public int[] layers;public float[] initialWeights;public float initialWeight=1; }
    // A character-local adapter to Unity's own Animator. No downloaded scripts,
    // event callbacks or networking components enter the player.
    public sealed class AvatarControlDriver : MonoBehaviour
    {
        public Animator animator;
        public AvatarControlProfile profile;
        public AvatarLayerGroup[] layerGroups;
        bool initialized;
        public bool AllowBlink {get;private set;}=true;
        public bool AllowSpeech {get;private set;}=true;
        readonly Dictionary<string,float> weights=new Dictionary<string,float>();
        readonly Dictionary<string,Fade> fades=new Dictionary<string,Fade>();
        sealed class Fade {public float start,target,duration,elapsed;}
        public bool Available => animator && profile!=null;
        public CharacterParameterValue[] Values => profile.controls.Select(c=>new CharacterParameterValue {id=c.id,value=c.kind=="slider"?Mathf.InverseLerp(c.minimum,c.maximum,Get(c.parameter)):Get(c.parameter)}).ToArray();
        void OnEnable() { if(!initialized && Available) {Reset();initialized=true;} }
        public float Get(string parameter)
        {
            var p=profile.parameters.FirstOrDefault(v=>v.name==parameter);
            return p==null?0:p.kind=="bool" || p.kind=="trigger"?(animator.GetBool(parameter)?1:0):p.kind=="int"?animator.GetInteger(parameter):animator.GetFloat(parameter);
        }
        public void Set(string parameter,float value)
        {
            var p=profile.parameters.FirstOrDefault(v=>v.name==parameter);
            if(p==null || !float.IsFinite(value))return;
            if(p.kind=="bool")animator.SetBool(parameter,value>.5f);
            else if(p.kind=="trigger") {if(value>.5f)animator.SetTrigger(parameter);else animator.ResetTrigger(parameter);}
            else if(p.kind=="int")animator.SetInteger(parameter,Mathf.RoundToInt(value));
            else animator.SetFloat(parameter,value);
        }
        public string Select(string id,float normalized)
        {
            var c=profile.controls.FirstOrDefault(v=>v.id==id);
            if(c==null)return "AVATAR_CONTROL_UNKNOWN";
            foreach(var gate in c.gates??Array.Empty<AvatarGate>())Set(gate.parameter,gate.value);
            if(c.kind=="slider")Set(c.parameter,Mathf.Lerp(c.minimum,c.maximum,Mathf.Clamp01(normalized)));
            else Set(c.parameter,normalized>.001f?c.value:0);
            // The analog fist blend is a distinct VRChat parameter.
            if(c.parameter=="GestureLeft" || c.parameter=="GestureRight")Set(c.parameter+"Weight",Get(c.parameter)==1?1:0);
            if(c.kind=="button" && normalized>.5f)StartCoroutine(Release(c));
            return null;
        }
        IEnumerator Release(AvatarControl control) {yield return new WaitForSeconds(1);Set(control.parameter,0);}
        public void Reset(string group="")
        {
            if(string.IsNullOrEmpty(group))
            {
                StopAllCoroutines();animator.Rebind();
                AllowBlink=AllowSpeech=true;fades.Clear();weights.Clear();
                foreach(var g in layerGroups??Array.Empty<AvatarLayerGroup>())
                {
                    weights[g.playable+":-1"]=g.initialWeight;
                    for(int i=0;i<g.layers.Length;i++)weights[g.playable+":"+i]=g.initialWeights[i];
                }
                ApplyWeights();
                foreach(var p in profile.parameters)Set(p.name,p.initial);
                Set("IsLocal",1);Set("Grounded",1);Set("TrackingType",3);Set("Upright",1);
            }
            else foreach(var c in profile.controls.Where(c=>c.group==group))
            {
                Set(c.parameter,c.initial);
                foreach(var gate in c.gates??Array.Empty<AvatarGate>())Set(gate.parameter,profile.parameters.First(p=>p.name==gate.parameter).initial);
                if(c.parameter=="GestureLeft" || c.parameter=="GestureRight")Set(c.parameter+"Weight",0);
            }
            animator.Update(0);
        }
        public void Weight(int playable,int layer,float weight,float seconds)
        {
            var group=layerGroups.FirstOrDefault(g=>g.playable==playable);if(group==null)return;
            if(layer==0 || layer>=group.layers.Length)return; // controller layer 0 is always 1
            string key=playable+":"+layer;float target=Mathf.Clamp01(weight);
            if(seconds<=0) {fades.Remove(key);weights[key]=target;ApplyWeights();return;}
            fades[key]=new Fade {start=weights.TryGetValue(key,out var v)?v:1,target=target,duration=seconds};
        }
        void Update(){AdvanceWeights(Time.deltaTime);}
        public void AdvanceWeights(float dt)
        {
            if(fades.Count==0)return;
            foreach(string key in fades.Keys.ToArray())
            {var f=fades[key];f.elapsed+=dt;weights[key]=Mathf.Lerp(f.start,f.target,Mathf.Clamp01(f.elapsed/f.duration));if(f.elapsed>=f.duration)fades.Remove(key);}
            ApplyWeights();
        }
        void ApplyWeights()
        {
            foreach(var g in layerGroups??Array.Empty<AvatarLayerGroup>())
                for(int i=0;i<g.layers.Length;i++)animator.SetLayerWeight(g.layers[i],weights[g.playable+":-1"]*weights[g.playable+":"+i]);
        }
        public void Tracking(int eyes,int mouth) {if(eyes!=0)AllowBlink=eyes==1;if(mouth!=0)AllowSpeech=mouth==1;}
    }
    [Serializable] public sealed class AvatarParameterOperation
    {
        public string name,source;public int operation;
        public float value,minimum,maximum,chance=1,sourceMin,sourceMax=1,destMin,destMax=1;
        public bool convertRange;
    }
    [Serializable] public sealed class AvatarBehavior
    {
        public string kind;public bool localOnly;public AvatarParameterOperation[] parameters;
        public int playable,layer=-1;public float weight,duration;
        public int eyes,mouth;
    }
}
