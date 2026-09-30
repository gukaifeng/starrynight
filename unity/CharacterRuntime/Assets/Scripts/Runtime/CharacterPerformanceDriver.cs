using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class CharacterPerformanceGroup { public string id,label,symbol; }
    [Serializable] public sealed class CharacterAIPerformanceHint {
        public string intent,kind;
        public string[] effects,moods,conflicts;
        public bool automatic,speechCompatible;
        public float cooldownSeconds=3;
    }
    [Serializable] public sealed class CharacterVisibility { public string path; public bool visible; }
    [Serializable] public sealed class CharacterMorphKey { public float time,value; }
    [Serializable] public sealed class CharacterMorphTrack
    {
        public string renderer,shape;
        public CharacterMorphKey[] keys=Array.Empty<CharacterMorphKey>();
    }
    [Serializable] public sealed class CharacterPerformanceOption
    {
        public string id,group,label,kind="preset",clip,offClip,next,description;
        public float duration;
        public bool loop,defaultOn,additive;
        public string[] bones=Array.Empty<string>();
        public ShapeBinding[] morphs=Array.Empty<ShapeBinding>(),offMorphs=Array.Empty<ShapeBinding>();
        public CharacterMorphTrack[] morphTracks=Array.Empty<CharacterMorphTrack>();
        public CharacterVisibility[] visibility=Array.Empty<CharacterVisibility>(),offVisibility=Array.Empty<CharacterVisibility>();
        public CharacterAIPerformanceHint ai;
        public AvatarControl control;
    }
    [Serializable] public sealed class CharacterPerformanceProfile
    {
        public int schemaVersion=1;
        public CharacterPerformanceGroup[] groups=Array.Empty<CharacterPerformanceGroup>();
        public CharacterPerformanceOption[] options=Array.Empty<CharacterPerformanceOption>();
        public CharacterVisibility[] defaults=Array.Empty<CharacterVisibility>();
        public IEnumerable<string> Clips => options.SelectMany(o=>new[]{o.clip,o.offClip}).Where(c=>!string.IsNullOrEmpty(c)).Distinct();
    }
    public static class CharacterPerformanceContract
    {
        public static readonly string[] Groups={"expression","pose","hands","ears","tail","appearance"};
        // JsonUtility can materialize a missing optional class as an empty object.
        // Negotiation is based on authored options, never object non-nullness alone.
        public static bool IsSupported(CharacterPerformanceProfile profile) => profile?.options!=null && profile.options.Length>0;
        static bool Name(string value) => !string.IsNullOrWhiteSpace(value) && value.Length<=128;
        static bool Path(string value) => Name(value) && !value.StartsWith("/",StringComparison.Ordinal) &&
            !value.Contains("\\") && value.Split('/').All(p=>p.Length>0 && p!="." && p!="..");
        public static void Validate(CharacterPerformanceProfile p)
        {
            if(p==null)return;
            if((p.schemaVersion!=1 && p.schemaVersion!=2) || p.groups==null || p.groups.Length>(p.schemaVersion==1 ? 6 : 32) || p.options==null || p.options.Length>256 || p.defaults==null || p.defaults.Length>64)
                throw new ArgumentException("PERFORMANCE_SCHEMA_INVALID");
            if(p.groups.Any(g=>g==null || !Name(g.id) || (p.schemaVersion==1 ? !Groups.Contains(g.id) : !System.Text.RegularExpressions.Regex.IsMatch(g.id,@"^[a-z][a-z0-9_.-]{0,63}$")) || !Name(g.label)) || p.groups.Select(g=>g.id).Distinct().Count()!=p.groups.Length)
                throw new ArgumentException("PERFORMANCE_GROUP_INVALID");
            if(p.options.Any(o=>o==null || !Name(o.id)) || p.options.Select(o=>o.id).Distinct().Count()!=p.options.Length)
                throw new ArgumentException("PERFORMANCE_OPTION_ID_INVALID");
            void Shapes(ShapeBinding[] values)
            {
                if(values==null || values.Length>256 || values.Any(v=>v==null || !Path(v.renderer) || !Name(v.shape) || !float.IsFinite(v.weight) || v.weight<0 || v.weight>1) ||
                    values.Select(v=>v.renderer+"\n"+v.shape).Distinct().Count()!=values.Length)
                    throw new ArgumentException("PERFORMANCE_MORPH_INVALID");
            }
            void Visible(CharacterVisibility[] values)
            {
                if(values==null || values.Length>64 || values.Any(v=>v==null || !Path(v.path)) || values.Select(v=>v.path).Distinct().Count()!=values.Length)
                    throw new ArgumentException("PERFORMANCE_VISIBILITY_INVALID");
            }
            Visible(p.defaults);
            int trackCount=0;
            foreach(var o in p.options)
            {
                // Missing optional objects can deserialize as empty in JsonUtility.
                if(o.ai!=null && !string.IsNullOrEmpty(o.ai.intent)) {
                    var hint=o.ai;
                    if(!Name(hint.intent) || hint.effects==null || hint.effects.Length==0 || hint.effects.Length>8 || hint.effects.Any(e=>!Name(e)) ||
                       (hint.moods!=null && (hint.moods.Length>16 || hint.moods.Any(m=>!Name(m)))) ||
                       (hint.conflicts!=null && (hint.conflicts.Length>32 || hint.conflicts.Any(g=>g==o.group || !p.groups.Any(group=>group.id==g)))) ||
                       !float.IsFinite(hint.cooldownSeconds) || hint.cooldownSeconds<0 || hint.cooldownSeconds>300)
                        throw new ArgumentException("PERFORMANCE_AI_HINT_INVALID: "+o.id);
                }
                if(!p.groups.Any(g=>g.id==o.group) || !Name(o.label) || !new[]{"preset","motion","toggle"}.Contains(o.kind) ||
                    !float.IsFinite(o.duration) || o.duration<0 || o.duration>120 || o.bones==null || o.bones.Length>256 ||
                    o.bones.Any(b=>!Path(b)) || o.bones.Distinct().Count()!=o.bones.Length ||
                    (!string.IsNullOrEmpty(o.clip) && (!Name(o.clip) || o.bones.Length==0)) || o.morphTracks==null ||
                    (o.kind=="motion" && string.IsNullOrEmpty(o.clip) && o.morphTracks.Length==0))
                    throw new ArgumentException("PERFORMANCE_OPTION_INVALID: "+o.id);
                if(!string.IsNullOrEmpty(o.offClip) && (o.kind!="toggle" || !Name(o.offClip) || o.bones.Length==0))
                    throw new ArgumentException("PERFORMANCE_OFF_CLIP_INVALID: "+o.id);
                if(!string.IsNullOrEmpty(o.next) && (o.kind!="motion" || o.loop || o.next==o.id ||
                    !p.options.Any(target=>target.id==o.next && target.group==o.group && target.kind!="toggle")))
                    throw new ArgumentException("PERFORMANCE_NEXT_INVALID: "+o.id);
                Shapes(o.morphs);Shapes(o.offMorphs);Visible(o.visibility);Visible(o.offVisibility);
                trackCount+=o.morphTracks.Length;
                if(trackCount>256 || o.morphTracks.Any(t=>t==null || !Path(t.renderer) || !Name(t.shape)) ||
                    o.morphTracks.Select(t=>t.renderer+"\n"+t.shape).Distinct().Count()!=o.morphTracks.Length)
                    throw new ArgumentException("PERFORMANCE_MORPH_TRACK_INVALID: "+o.id);
                foreach(var track in o.morphTracks)
                {
                    if(track.keys==null || track.keys.Length==0 || track.keys.Length>7201)
                        throw new ArgumentException("PERFORMANCE_MORPH_KEYS_INVALID: "+o.id);
                    float previous=-1;
                    foreach(var key in track.keys)
                    {
                        if(key==null || !float.IsFinite(key.time) || key.time<0 || key.time>120 || key.time<=previous ||
                            !float.IsFinite(key.value) || key.value<0 || key.value>1)
                            throw new ArgumentException("PERFORMANCE_MORPH_KEY_INVALID: "+o.id);
                        previous=key.time;
                    }
                }
                if(o.kind!="toggle" && (o.offMorphs.Length>0 || o.offVisibility.Length>0))
                    throw new ArgumentException("PERFORMANCE_OFF_REQUIRES_TOGGLE: "+o.id);
            }
            foreach(var group in p.groups)
                if(p.options.Count(o=>o.group==group.id && o.kind!="toggle" && o.defaultOn)>1)
                    throw new ArgumentException("PERFORMANCE_DEFAULT_CONFLICT: "+group.id);
        }
    }

    // Explicit author controls sit above speech / semantic expressions. The paired early
    // restore component unwinds this overlay BEFORE those lower layers restore themselves.
    [DefaultExecutionOrder(60)]
    public sealed class CharacterPerformanceDriver : MonoBehaviour
    {
        sealed class Morph { public SkinnedMeshRenderer skin;public int index;public float scale,initial,baseline,value; }
        sealed class Visible { public Renderer renderer;public bool initial,value; }
        sealed class Track {public Morph slot;public CharacterMorphTrack spec;}
        sealed class Entry
        {
            public CharacterPerformanceOption spec;
            public bool selected;public float weight,elapsed,duration;public int order;
            public AnimationState animation,offAnimation;public string alias,offAlias;
            public bool transientPlaying,playingOff;public float transientElapsed,transientWeight;
            public Morph[] touched=Array.Empty<Morph>();
            public Track[] tracks=Array.Empty<Track>();
            public readonly Dictionary<Morph,float> onMorphs=new Dictionary<Morph,float>(),offMorphs=new Dictionary<Morph,float>();
            public readonly Dictionary<Visible,bool> onVisible=new Dictionary<Visible,bool>(),offVisible=new Dictionary<Visible,bool>();
        }
        readonly List<Morph> morphs=new List<Morph>();
        readonly List<Visible> visibility=new List<Visible>();
        readonly List<Entry> entries=new List<Entry>();
        readonly List<string> successors=new List<string>();
        ViewerCharacter character;Animation player;
        int order;bool applied;
        float poseWeight;
        public Action OnChanged;
        public bool Supported => character && CharacterPerformanceContract.IsSupported(character.Manifest.performance);
        public bool Transitioning { get; private set; }
        public float GazeWeight => 1-poseWeight;
        public string[] Selections => entries.Where(e=>{
            if(!string.IsNullOrEmpty(e.spec.control?.id)) {
                var avatar=character?character.GetComponent<AvatarControlDriver>():null;
                return avatar && Mathf.Abs(avatar.Get(e.spec.control.parameter)-e.spec.control.value)<.001f;
            }
            return e.selected;
        }).Select(e=>e.spec.id).ToArray();
        // Includes the outgoing pose/expression until its blend completes.
        public float WeightFor(string[] groups,string[] options)
        {
            float weight=0;
            foreach(var entry in entries)
                if((groups!=null && Array.IndexOf(groups,entry.spec.group)>=0) || (options!=null && Array.IndexOf(options,entry.spec.id)>=0))
                    weight+=entry.weight;
            return Mathf.Clamp01(weight);
        }
        public void Bind(ViewerCharacter c)
        {
            Clear();character=c;player=c.GetComponentInChildren<Animation>(true);
            var restore=GetComponent<CharacterPerformanceRestore>() ?? gameObject.AddComponent<CharacterPerformanceRestore>();restore.driver=this;
            var profile=c.Manifest.performance;if(!CharacterPerformanceContract.IsSupported(profile))return;
            Morph Shape(ShapeBinding binding)
            {
                var skin=CharacterContract.Resolve(c.transform,binding.renderer)?.GetComponent<SkinnedMeshRenderer>();
                int index=skin ? skin.sharedMesh.GetBlendShapeIndex(binding.shape) : -1;
                if(index<0)throw new ArgumentException("PERFORMANCE_MORPH_MISSING: "+binding.renderer+"/"+binding.shape);
                var slot=morphs.Find(s=>s.skin==skin && s.index==index);
                if(slot==null) {slot=new Morph {skin=skin,index=index,scale=CharacterContract.MorphScale(skin,index),initial=skin.GetBlendShapeWeight(index)};morphs.Add(slot);}return slot;
            }
            Visible Renderer(string path)
            {
                var renderer=CharacterContract.Resolve(c.transform,path)?.GetComponent<Renderer>();
                if(!renderer)throw new ArgumentException("PERFORMANCE_RENDERER_MISSING: "+path);
                var slot=visibility.Find(s=>s.renderer==renderer);
                if(slot==null) {slot=new Visible {renderer=renderer,initial=renderer.enabled};visibility.Add(slot);}return slot;
            }
            foreach(var value in profile.defaults) {var slot=Renderer(value.path);slot.initial=value.visible;slot.renderer.enabled=value.visible;}
            foreach(var option in profile.options)
            {
                var entry=new Entry {spec=option,selected=option.defaultOn,weight=option.defaultOn?1:0,order=++order};
                foreach(var b in option.morphs)entry.onMorphs[Shape(b)]=b.weight;
                foreach(var b in option.offMorphs)entry.offMorphs[Shape(b)]=b.weight;
                entry.tracks=option.morphTracks.Select(t=>new Track {slot=Shape(new ShapeBinding {renderer=t.renderer,shape=t.shape}),spec=t}).ToArray();
                entry.touched=entry.onMorphs.Keys.Concat(entry.offMorphs.Keys).Concat(entry.tracks.Select(t=>t.slot)).Distinct().ToArray();
                foreach(var b in option.visibility)entry.onVisible[Renderer(b.path)]=b.visible;
                foreach(var b in option.offVisibility)entry.offVisible[Renderer(b.path)]=b.visible;
                AnimationState MakeState(string name,string alias)
                {
                    if(string.IsNullOrEmpty(name))return null;
                    var clip=player?player.GetClip(name):null;
                    if(!clip)throw new ArgumentException("PERFORMANCE_CLIP_MISSING: "+name);
                    player.AddClip(clip,alias);var state=player[alias];
                    state.layer=10+Array.FindIndex(profile.groups,g=>g.id==option.group);
                    state.blendMode=option.additive?AnimationBlendMode.Additive:AnimationBlendMode.Blend;
                    state.wrapMode=option.loop && option.kind!="toggle"?WrapMode.Loop:WrapMode.ClampForever;
                    foreach(var path in option.bones)
                    {
                        var bone=CharacterContract.Resolve(c.transform,path);
                        if(!bone)throw new ArgumentException("PERFORMANCE_BONE_MISSING: "+path);
                        state.AddMixingTransform(bone,false);
                    }
                    state.enabled=false;state.time=0;state.weight=0;return state;
                }
                entry.alias="__performance_"+option.id;entry.offAlias=entry.alias+"_off";
                entry.animation=MakeState(option.clip,entry.alias);entry.offAnimation=MakeState(option.offClip,entry.offAlias);
                entry.duration=option.duration>0?option.duration:Mathf.Max(entry.animation?.length ?? 0,
                    option.morphTracks.Select(t=>t.keys[t.keys.Length-1].time).DefaultIfEmpty(0).Max());
                if(entry.animation!=null && option.kind!="toggle") {entry.animation.enabled=entry.selected;entry.animation.weight=entry.weight;}
                entries.Add(entry);
            }
            ApplyVisibility();UpdatePoseWeight();
        }
        public string Select(string id,float intensity)
        {
            if(!Supported)return "PERFORMANCE_UNSUPPORTED";
            var entry=entries.Find(e=>e.spec.id==id);if(entry==null)return "PERFORMANCE_OPTION_UNKNOWN";
            if(!string.IsNullOrEmpty(entry.spec.control?.id)) {
                var avatar=character.GetComponent<AvatarControlDriver>();
                if(!avatar)return "AVATAR_CONTROL_UNAVAILABLE";
                var error=avatar.Select(entry.spec.control.id,intensity);OnChanged?.Invoke();return error;
            }
            bool selected=entry.spec.kind!="toggle" || intensity>=.5f;
            if(selected && entry.spec.kind!="toggle")
                foreach(var other in entries)if(other.spec.group==entry.spec.group && other.spec.kind!="toggle")other.selected=false;
            bool changed=selected!=entry.selected;
            bool restart=selected && (!entry.selected || entry.spec.kind=="motion");
            entry.selected=selected;entry.order=++order;entries.Sort((a,b)=>a.order.CompareTo(b.order));
            if(restart) {entry.elapsed=0;if(entry.animation!=null)entry.animation.time=0;}
            if(entry.spec.kind=="toggle" && changed)
            {
                entry.playingOff=!selected;entry.transientElapsed=0;
                var state=entry.playingOff?entry.offAnimation:entry.animation;
                entry.transientPlaying=state!=null;
                if(state!=null) {state.time=0;state.enabled=true;}
            }
            else if(entry.animation!=null && selected && entry.spec.kind!="toggle")entry.animation.enabled=true;
            Transitioning=true;OnChanged?.Invoke();return null;
        }
        public string Reset(string group="")
        {
            if(!Supported)return "PERFORMANCE_UNSUPPORTED";
            if(!string.IsNullOrEmpty(group) && !character.Manifest.performance.groups.Any(g=>g.id==group))return "PERFORMANCE_GROUP_UNKNOWN";
            var avatar=character.GetComponent<AvatarControlDriver>();
            if(avatar)avatar.Reset(string.IsNullOrEmpty(group)?"":character.Manifest.performance.options.First(o=>o.group==group).control?.group ?? "");
            foreach(var entry in entries)
                if(string.IsNullOrEmpty(group) || entry.spec.group==group)
                {entry.selected=entry.spec.defaultOn;entry.elapsed=0;entry.transientPlaying=false;if(entry.animation!=null && entry.selected && entry.spec.kind!="toggle") {entry.animation.time=0;entry.animation.enabled=true;}}
            Transitioning=true;OnChanged?.Invoke();return null;
        }
        public void RestoreMorphs()
        {
            if(!applied)return;
            foreach(var slot in morphs)if(slot.skin)slot.skin.SetBlendShapeWeight(slot.index,slot.baseline);
            applied=false;
        }
        public void Clear()
        {
            RestoreMorphs();
            foreach(var slot in morphs)if(slot.skin)slot.skin.SetBlendShapeWeight(slot.index,slot.initial);
            foreach(var slot in visibility)if(slot.renderer)slot.renderer.enabled=slot.initial;
            foreach(var entry in entries)
            {
                if(entry.animation!=null) {entry.animation.weight=0;entry.animation.enabled=false;if(player)player.RemoveClip(entry.alias);}
                if(entry.offAnimation!=null) {entry.offAnimation.weight=0;entry.offAnimation.enabled=false;if(player)player.RemoveClip(entry.offAlias);}
            }
            entries.Clear();morphs.Clear();visibility.Clear();successors.Clear();character=null;player=null;order=0;poseWeight=0;Transitioning=false;
        }
        void OnDisable() { Clear(); }
        void Update() { Step(Time.unscaledDeltaTime); }
        public void Step(float deltaTime)
        {
            if(!character || !character.gameObject.activeInHierarchy)return;
            float dt=Mathf.Clamp(deltaTime,0,.05f),alpha=1-Mathf.Exp(-9*dt);
            bool before=Transitioning,changed=false;Transitioning=false;
            successors.Clear();
            foreach(var entry in entries)
            {
                if(entry.selected)entry.elapsed+=dt;
                if(entry.selected && entry.spec.kind=="motion" && !entry.spec.loop)
                {
                    if(entry.elapsed>=Mathf.Max(.1f,entry.duration))
                    {entry.selected=false;changed=true;if(!string.IsNullOrEmpty(entry.spec.next))successors.Add(entry.spec.next);}
                }
            }
            // Change all targets before applying this frame's blend weights, so an
            // authored transition into a sleep loop never drops through standing Idle.
            foreach(string next in successors)Select(next,1);
            foreach(var entry in entries)
            {
                float target=entry.selected?1:0;entry.weight=Mathf.Lerp(entry.weight,target,alpha);
                if(Mathf.Abs(entry.weight-target)<.0005f)entry.weight=target;else Transitioning=true;
                if(entry.spec.kind=="toggle")
                {
                    var state=entry.playingOff?entry.offAnimation:entry.animation;
                    if(entry.transientPlaying) {entry.transientElapsed+=dt;if(entry.transientElapsed>=Mathf.Max(.1f,state.length))entry.transientPlaying=false;}
                    entry.transientWeight=Mathf.Lerp(entry.transientWeight,entry.transientPlaying?1:0,alpha);
                    if(!entry.transientPlaying && entry.transientWeight<.0005f)entry.transientWeight=0;
                    Transitioning|=entry.transientPlaying || entry.transientWeight>0;
                    if(entry.animation!=null) {entry.animation.weight=entry.playingOff?0:entry.transientWeight;entry.animation.enabled=entry.animation.weight>0;}
                    if(entry.offAnimation!=null) {entry.offAnimation.weight=entry.playingOff?entry.transientWeight:0;entry.offAnimation.enabled=entry.offAnimation.weight>0;}
                }
                else if(entry.animation!=null)
                {entry.animation.weight=entry.weight;entry.animation.enabled=entry.weight>0 || entry.selected;}
            }
            UpdatePoseWeight();
            if(changed || before && !Transitioning)OnChanged?.Invoke();
        }
        void UpdatePoseWeight()
        {
            poseWeight=0;
            foreach(var entry in entries)
                if(entry.spec.group=="pose" && entry.animation!=null && !entry.spec.additive)
                    poseWeight+=entry.spec.kind=="toggle"?entry.transientWeight:entry.weight;
            poseWeight=Mathf.Clamp01(poseWeight);
        }
        void ApplyVisibility()
        {
            foreach(var slot in visibility)slot.value=slot.initial;
            foreach(var entry in entries)
            {
                var values=entry.weight>=.5f?entry.onVisible:entry.offVisible;
                foreach(var binding in values)binding.Key.value=binding.Value;
            }
            foreach(var slot in visibility)if(slot.renderer && slot.renderer.enabled!=slot.value)slot.renderer.enabled=slot.value;
        }
        void LateUpdate() { ApplyFrame(); }
        public void ApplyFrame()
        {
            if(!character || !character.gameObject.activeInHierarchy)return;
            foreach(var slot in morphs) {slot.baseline=slot.skin.GetBlendShapeWeight(slot.index);slot.value=slot.baseline;}
            foreach(var entry in entries)
            {
                // Explicit off values are authored states too. Omitted off restores the
                // underlying live speech/expression/animation value instead of freezing it.
                if(entry.weight<=0 && entry.offMorphs.Count==0)continue;
                foreach(var slot in entry.touched)
                {
                    bool on=entry.onMorphs.TryGetValue(slot,out float onValue),off=entry.offMorphs.TryGetValue(slot,out float offValue);
                    if(!on && !off)continue;
                    float origin=off?offValue*slot.scale:slot.value,target=on?onValue*slot.scale:slot.value;
                    slot.value=Mathf.Lerp(origin,target,entry.weight);
                }
                float time=entry.spec.loop && entry.duration>0 ? Mathf.Repeat(entry.elapsed,entry.duration) : Mathf.Min(entry.elapsed,entry.duration);
                foreach(var track in entry.tracks)
                    track.slot.value=Mathf.Lerp(track.slot.value,Evaluate(track.spec,time)*track.slot.scale,entry.weight);
            }
            foreach(var slot in morphs)slot.skin.SetBlendShapeWeight(slot.index,Mathf.Clamp(slot.value,0,slot.scale));
            applied=true;ApplyVisibility();
        }
        // Source curves are sampled during import. Bounded binary search preserves their
        // authored timing without evaluating source scripts or allocating per-frame curves.
        public static float Evaluate(CharacterMorphTrack track,float time)
        {
            var keys=track.keys;
            if(time<=keys[0].time)return keys[0].value;
            int last=keys.Length-1;if(time>=keys[last].time)return keys[last].value;
            int low=0,high=last;
            while(high-low>1) {int middle=(low+high)/2;if(keys[middle].time<=time)low=middle;else high=middle;}
            float progress=(time-keys[low].time)/(keys[high].time-keys[low].time);
            return Mathf.Lerp(keys[low].value,keys[high].value,progress);
        }
    }
}
