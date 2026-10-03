using System;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class SourceMotionPreviewState
    {
        public string id="",label="",origin="author-curves-host-preview";
        public int count,started,completed;
        public float weight,time;
        public bool loop,held;
    }
    // Actor-local, data-only original clip inspection. Every property written
    // by SampleAnimation is unwound BEFORE Animator's next baseline evaluation.
    // A clip cannot leave a costume, face or bone pose behind after stopping.
    [DefaultExecutionOrder(75)]
    public sealed class SourceMotionPreview:MonoBehaviour
    {
        public const string Parameter="Starry_SourceMotion";
        [Serializable] public sealed class Node {public Transform target;public bool transform,active;}
        [Serializable] public sealed class Morph {public SkinnedMeshRenderer skin;public int index;}
        [Serializable] public sealed class Visible {public Renderer target;}
        [Serializable] public sealed class Entry
        {
            public string id,label,category,intent;public AnimationClip clip;public float duration;public bool loop;
            public Node[] nodes=Array.Empty<Node>();public Morph[] morphs=Array.Empty<Morph>();public Visible[] visible=Array.Empty<Visible>();
        }
        public Entry[] entries=Array.Empty<Entry>();
        public GameObject avatar;
        public SourceMotionPreviewState State {get;private set;}=new SourceMotionPreviewState();
        public Action OnChanged;
        AvatarControlDriver author;
        Entry current;string queued="";
        Vector3[] positions=Array.Empty<Vector3>(),scales=Array.Empty<Vector3>();
        Quaternion[] rotations=Array.Empty<Quaternion>();
        bool[] active=Array.Empty<bool>(),visible=Array.Empty<bool>();float[] morphs=Array.Empty<float>();
        bool applied,reported;float elapsed,release=-1,releaseWeight;
        public bool Active=>current!=null;
        void Awake(){author=GetComponent<AvatarControlDriver>();State.count=entries.Length;}
        void OnEnable(){State.count=entries.Length;}
        public string Select(string id)
        {
            if(!Array.Exists(entries,e=>e.id==id))return "SOURCE_MOTION_UNKNOWN";
            if(current!=null){Cancel();queued=id;}else StartClip(id);
            return null;
        }
        void StartClip(string id)
        {
            current=Array.Find(entries,e=>e.id==id);elapsed=0;release=-1;queued="";reported=false;
            positions=new Vector3[current.nodes.Length];scales=new Vector3[positions.Length];rotations=new Quaternion[positions.Length];active=new bool[positions.Length];
            visible=new bool[current.visible.Length];morphs=new float[current.morphs.Length];
            State.count=entries.Length;State.id=id;State.label=current.label;State.time=State.weight=0;State.loop=current.loop;State.held=current.duration<=.05f;State.started++;
            if(!author)author=GetComponent<AvatarControlDriver>();
            if(author)author.animator.SetInteger(Parameter,Array.IndexOf(entries,current)+1);
            OnChanged?.Invoke();
        }
        public void Cancel()
        {
            queued="";
            if(current!=null && release<0){release=0;releaseWeight=State.weight;}
        }
        public void Clear()
        {
            RestorePose();current=null;queued="";release=-1;
            State.id=State.label="";State.time=State.weight=0;
            if(author)author.animator.SetInteger(Parameter,0);
        }
        void LateUpdate(){Step(Time.unscaledDeltaTime);}
        void OnDisable(){Clear();}
        public void Step(float dt)
        {
            RestorePose();if(current==null || !avatar || !gameObject.activeInHierarchy)return;
            dt=Mathf.Clamp(dt,0,.05f);elapsed+=dt;
            if(release>=0){release+=dt;State.weight=releaseWeight*(1-HostEmotionMotion.Smooth(release/.48f));}
            else State.weight=HostEmotionMotion.Smooth(elapsed/.42f);
            float clipTime=Mathf.Max(0,elapsed-.42f);
            if(!State.held && !current.loop && clipTime>=current.duration && release<0){release=0;releaseWeight=State.weight;}
            if(release>=.48f){string next=queued;queued="";Clear();State.completed++;OnChanged?.Invoke();if(next.Length>0)StartClip(next);return;}
            // One/two-frame authoring clips often encode a slider or toggle
            // from 0 to its target. Hold the target, not its unchanged first key.
            State.time=State.held?current.duration:current.loop?clipTime%Mathf.Max(.05f,current.duration):Mathf.Min(clipTime,current.duration);
            for(int i=0;i<current.nodes.Length;i++){
                var t=current.nodes[i].target;positions[i]=t.localPosition;rotations[i]=t.localRotation;scales[i]=t.localScale;active[i]=t.gameObject.activeSelf;
            }
            for(int i=0;i<current.morphs.Length;i++)morphs[i]=current.morphs[i].skin.GetBlendShapeWeight(current.morphs[i].index);
            for(int i=0;i<current.visible.Length;i++)visible[i]=current.visible[i].target.enabled;
            current.clip.SampleAnimation(avatar,State.time);
            for(int i=0;i<current.nodes.Length;i++){
                var node=current.nodes[i];var t=node.target;
                if(node.transform){t.localPosition=Vector3.LerpUnclamped(positions[i],t.localPosition,State.weight);t.localRotation=Quaternion.SlerpUnclamped(rotations[i],t.localRotation,State.weight);t.localScale=Vector3.LerpUnclamped(scales[i],t.localScale,State.weight);}
                if(node.active && State.weight<.5f)t.gameObject.SetActive(active[i]);
            }
            for(int i=0;i<current.morphs.Length;i++){var m=current.morphs[i];m.skin.SetBlendShapeWeight(m.index,Mathf.Lerp(morphs[i],m.skin.GetBlendShapeWeight(m.index),State.weight));}
            for(int i=0;i<current.visible.Length;i++)if(State.weight<.5f)current.visible[i].target.enabled=visible[i];
            applied=true;
            if(!reported && elapsed>=.65f){reported=true;OnChanged?.Invoke();}
        }
        public void RestorePose()
        {
            if(!applied || current==null)return;
            for(int i=0;i<current.nodes.Length;i++){
                var node=current.nodes[i];var t=node.target;if(!t)continue;
                if(node.transform){t.localPosition=positions[i];t.localRotation=rotations[i];t.localScale=scales[i];}
                if(node.active)t.gameObject.SetActive(active[i]);
            }
            for(int i=0;i<current.morphs.Length;i++){var m=current.morphs[i];if(m.skin)m.skin.SetBlendShapeWeight(m.index,morphs[i]);}
            for(int i=0;i<current.visible.Length;i++)if(current.visible[i].target)current.visible[i].target.enabled=visible[i];
            applied=false;
        }
    }
}
