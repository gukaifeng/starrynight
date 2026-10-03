using System;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    // Conversation-only continuity above the author's Animator, below lip-sync,
    // blink, gaze and spring motion. Source clips and their timings are intact.
    [DefaultExecutionOrder(40)]
    public sealed class AvatarPoseContinuity : MonoBehaviour
    {
        [Serializable] public sealed class Bone {
            public Transform target;
            [NonSerialized] public Vector3 rawPosition,rawScale,shownPosition,shownScale,fromPosition,fromScale;
            [NonSerialized] public Quaternion rawRotation,shownRotation,fromRotation;
        }
        [Serializable] public sealed class Morph {
            public SkinnedMeshRenderer skin;public int index;
            [NonSerialized] public float raw,shown,from,range;
        }
        public Bone[] bones=Array.Empty<Bone>();
        public Morph[] morphs=Array.Empty<Morph>();
        bool initialized,applied,blending;
        float elapsed;
        AvatarControlDriver driver;
        readonly Dictionary<string,float> observedParameters=new Dictionary<string,float>();
        public bool Transitioning=>blending;
        public void Begin()
        {
            if(!initialized)return;
            foreach(var b in bones){b.fromPosition=b.shownPosition;b.fromRotation=b.shownRotation;b.fromScale=b.shownScale;}
            foreach(var m in morphs)m.from=m.shown;
            elapsed=0;blending=true;
        }
        public void Restore()
        {
            if(!applied)return;
            foreach(var b in bones)if(b.target){b.target.localPosition=b.rawPosition;b.target.localRotation=b.rawRotation;b.target.localScale=b.rawScale;}
            foreach(var m in morphs)if(m.skin)m.skin.SetBlendShapeWeight(m.index,m.raw);
            applied=false;
        }
        void Update(){Restore();}
        void LateUpdate(){Apply(Time.unscaledDeltaTime);}
        public void Apply(float dt)
        {
            // Authored state behaviours can change parameters inside Animator,
            // bypassing the host Set path. Blend these boundaries as well.
            if(!driver)driver=GetComponent<AvatarControlDriver>();
            bool changed=false;
            if(driver)foreach(string parameter in driver.conversationalParameters) {
                float value=driver.Get(parameter);
                if(observedParameters.TryGetValue(parameter,out float previous) && Mathf.Abs(previous-value)>.00001f)changed=true;
                observedParameters[parameter]=value;
            }
            if(changed)Begin();
            // A state can relinquish unkeyed/write-default channels one frame
            // after its blend ends, without changing a parameter. Treat a sharp
            // native pose discontinuity as another boundary, never a hard snap.
            if(initialized && !blending && driver && driver.Get(SourceMotionPreview.Parameter)<=0) {
                float limit=360*Mathf.Clamp(dt,0,.1f)+.1f;
                foreach(var b in bones)if(b.target && Quaternion.Angle(b.shownRotation,b.target.localRotation)>limit){Begin();break;}
            }
            if(blending)elapsed+=Mathf.Clamp(dt,0,.1f);
            float t=blending?Mathf.Clamp01(elapsed/AvatarControlDriver.ConversationBlendSeconds):1;
            t=t*t*t*(t*(t*6-15)+10); // zero acceleration at both endpoints
            bool bridge=blending,settling=false;
            foreach(var b in bones)if(b.target) {
                b.rawPosition=b.target.localPosition;b.rawRotation=b.target.localRotation;b.rawScale=b.target.localScale;
                b.shownPosition=blending?Vector3.Lerp(b.fromPosition,b.rawPosition,t):b.rawPosition;
                var desired=blending?Quaternion.Slerp(b.fromRotation,b.rawRotation,t):b.rawRotation;
                // Interrupted native transitions can change the target itself.
                // Bound angular speed and let the bridge settle instead of
                // snapping to a new target on the final transition frame.
                b.shownRotation=blending?Quaternion.RotateTowards(b.shownRotation,desired,360*Mathf.Clamp(dt,0,.1f)):desired;
                if(blending && Quaternion.Angle(b.shownRotation,desired)>.01f)settling=true;
                b.shownScale=blending?Vector3.Lerp(b.fromScale,b.rawScale,t):b.rawScale;
                if(bridge){b.target.localPosition=b.shownPosition;b.target.localRotation=b.shownRotation;b.target.localScale=b.shownScale;}
            }
            foreach(var m in morphs)if(m.skin) {
                m.raw=m.skin.GetBlendShapeWeight(m.index);
                if(m.range<=0)m.range=Mathf.Max(.001f,CharacterContract.MorphScale(m.skin,m.index));
                float desired=Mathf.Lerp(m.from,m.raw,t);
                m.shown=bridge?Mathf.MoveTowards(m.shown,desired,m.range*6*Mathf.Clamp(dt,0,.1f)):m.raw;
                if(bridge && Mathf.Abs(m.shown-desired)>m.range*.0001f)settling=true;
                if(bridge)m.skin.SetBlendShapeWeight(m.index,m.shown);
            }
            initialized=true;applied=bridge;if(elapsed>=AvatarControlDriver.ConversationBlendSeconds && !settling)blending=false;
        }
        public void Reset(){Restore();initialized=blending=false;elapsed=0;observedParameters.Clear();}
        void OnDisable(){Reset();}
    }
}
