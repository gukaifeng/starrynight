using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;

namespace ModelSpace
{
    [Serializable] public class PaletteTone
    {
        public float hue, saturation = 1, exposure, tint;
        public Vector4 Vector => new Vector4(hue / 360, saturation, exposure, tint);
        public static Vector4 Normalize(PaletteTone t)
        {
            if (t == null || !Finite(t.hue) || !Finite(t.saturation) || !Finite(t.exposure) || !Finite(t.tint))
                throw new ArgumentException("Invalid palette tone");
            return new Vector4(Mathf.Clamp(t.hue,-180,180)/360,Mathf.Clamp(t.saturation,0,2),Mathf.Clamp(t.exposure,-2,2),Mathf.Clamp01(t.tint));
        }
        static bool Finite(float x) => !float.IsNaN(x) && !float.IsInfinity(x);
    }
    [Serializable] public class PaletteEdit { public string component, channel; public PaletteTone tone; }
    [Serializable] public class PaletteChannel { public string id, label; public Color color; public bool hdr; }
    [Serializable] public class PaletteComponent
    {
        public string id, name, path, material, shader;
        public bool visible, supported;
        public int slot;
        public PaletteChannel[] channels;
    }
    [Serializable] public class PaletteSnapshot
    {
        public int revision = 1;
        public int editedSlots;
        public string modelId;
        public PaletteComponent[] components;
    }
    [Serializable] public class PaletteShaderEntry { public string original; public Shader shader; }
    [Serializable] public class PaletteMaterialLabel { public string key, label; }
    /// Host-only, non-destructive grading. Created lazily on both built-in and
    /// old downloaded prefabs; no prefab/bundle upgrade or source mutation needed.
    [DefaultExecutionOrder(250)]
    public sealed class CharacterPaletteRuntime : MonoBehaviour
    {
        public static readonly Vector4 Neutral = new Vector4(0,1,0,0);
        static readonly string[] Bands = {"$main","$shadow","$highlight"};
        static readonly string[] Uniforms = {"_StarryPaletteMain","_StarryPaletteShadow","_StarryPaletteHighlight"};
        sealed class Slot
        {
            public string id, path;
            public Renderer renderer;
            public int index;
            public Material original, clone;
            public bool resetting;
            public readonly Dictionary<string,Vector4> target = new Dictionary<string,Vector4>();
            public readonly Dictionary<string,Vector4> current = new Dictionary<string,Vector4>();
            public readonly Dictionary<string,Color> bases = new Dictionary<string,Color>(), written = new Dictionary<string,Color>();
        }
        readonly Dictionary<string,Slot> slots = new Dictionary<string,Slot>();
        MaterialPropertyBlock block;
        PaletteShaderLibrary library;
        public int EditedSlots => slots.Values.Count(x=>x.clone);
        public Action OnResetSettled;

        void Awake() { block = new MaterialPropertyBlock(); library = Resources.Load<PaletteShaderLibrary>("PaletteShaderLibrary"); Scan(); }
        string PathFor(Transform t)
        {
            var items = new List<string>();
            while(t && t!=transform) {items.Add(t.name+"["+t.GetSiblingIndex()+"]");t=t.parent;}
            items.Reverse();return string.Join("/",items);
        }
        void Scan()
        {
            foreach(var renderer in GetComponentsInChildren<Renderer>(true))
            {
                string path=PathFor(renderer.transform);
                int ordinal=Array.IndexOf(renderer.GetComponents<Renderer>(),renderer);
                var materials=renderer.sharedMaterials;
                for(int i=0;i<materials.Length;i++)
                {
                    if(!materials[i])continue;
                    string id=path+"#"+ordinal+":"+i;
                    if(!slots.ContainsKey(id)) slots.Add(id,new Slot {id=id,path=path,renderer=renderer,index=i,original=materials[i]});
                }
            }
        }
        static PaletteChannel[] Channels(Material m)
        {
            var result=new List<PaletteChannel>();
            for(int i=0;i<m.shader.GetPropertyCount();i++)
            {
                if(m.shader.GetPropertyType(i)!=ShaderPropertyType.Color)continue;
                var name=m.shader.GetPropertyName(i);
                result.Add(new PaletteChannel {id=name,label=Label(name),color=m.GetColor(name),hdr=(m.shader.GetPropertyFlags(i)&ShaderPropertyFlags.HDR)!=0});
            }
            return result.ToArray();
        }
        static string Label(string name)
        {
            switch(name)
            {
                case "_Color":return "主贴图色系";
                case "_ShadowColor":return "第一层阴影";
                case "_Shadow2ndColor":return "第二层阴影";
                case "_Shadow3rdColor":return "第三层阴影";
                case "_OutlineColor":return "轮廓线";
                case "_RimColor":return "边缘高光";
                case "_EmissionColor":return "自发光";
                case "_Emission2ndColor":return "第二层自发光";
                case "_MatCapColor":return "材质捕光";
                case "_MatCap2ndColor":return "第二层材质捕光";
                default:return name;
            }
        }
        public PaletteSnapshot Snapshot(string modelId)
        {
            Scan();
            return new PaletteSnapshot {modelId=modelId,editedSlots=EditedSlots,components=slots.Values.Where(x=>x.renderer && x.original).Select(x=>new PaletteComponent {
                id=x.id,path=x.path,name=x.renderer.name,material=library ? library.Label(x.original.name) : x.original.name,
                shader=x.original.shader.name,slot=x.index,visible=x.renderer.enabled && x.renderer.gameObject.activeInHierarchy,
                supported=library && library.Variant(x.original.shader),channels=Channels(x.original)
            }).ToArray()};
        }
        void Clone(Slot slot)
        {
            if(slot.clone)return;
            var shader=library ? library.Variant(slot.original.shader) : null;
            if(!shader)throw new ArgumentException("Palette shader unavailable for "+slot.original.shader.name);
            slot.clone=new Material(slot.original) {name=slot.original.name+" (Starry palette)",shader=shader};
            slot.clone.renderQueue=slot.original.renderQueue;
            slot.clone.shaderKeywords=slot.original.shaderKeywords;
            foreach(var uniform in Uniforms)slot.clone.SetVector(uniform,Neutral);
            var materials=slot.renderer.sharedMaterials;materials[slot.index]=slot.clone;slot.renderer.sharedMaterials=materials;
        }
        public void Edit(PaletteEdit edit)
        {
            if(edit==null || string.IsNullOrEmpty(edit.component) || !slots.TryGetValue(edit.component,out var slot))throw new ArgumentException("Unknown palette component");
            bool band=Bands.Contains(edit.channel);
            if(!band && !Channels(slot.original).Any(x=>x.id==edit.channel))throw new ArgumentException("Unknown palette channel");
            var tone=PaletteTone.Normalize(edit.tone);
            Clone(slot);slot.resetting=false;slot.target[edit.channel]=tone;
            if(!slot.current.ContainsKey(edit.channel))slot.current[edit.channel]=Neutral;
        }
        void LateUpdate() { Tick(Time.unscaledDeltaTime); }
        public void Tick(float delta)
        {
            // Iterate only edited slots. Untouched components cost no material
            // instances or per-frame shader work. Animation swaps are adopted.
            float response=1-Mathf.Exp(-Mathf.Max(0,delta)/.10f);
            bool restored=false;
            foreach(var slot in slots.Values)
            {
                if(!slot.clone || !slot.renderer)continue;
                var materials=slot.renderer.sharedMaterials;
                if(slot.index>=materials.Length)continue;
                if(materials[slot.index]!=slot.clone)
                {
                    if(!materials[slot.index])continue;
                    RestoreColors(slot);
                    DestroyMaterial(slot.clone);slot.clone=null;slot.original=materials[slot.index];
                    slot.bases.Clear();slot.written.Clear();Clone(slot);
                }
                slot.renderer.GetPropertyBlock(block,slot.index);
                foreach(var pair in slot.target)
                {
                    string channel=pair.Key;
                    var tone=Vector4.Lerp(slot.current[channel],pair.Value,response);
                    if((tone-pair.Value).sqrMagnitude<1e-8f)tone=pair.Value;
                    slot.current[channel]=tone;
                    int band=Array.IndexOf(Bands,channel);
                    if(band>=0) {slot.clone.SetVector(Uniforms[band],tone);continue;}
                    if(!slot.original.HasProperty(channel))continue;
                    int id=Shader.PropertyToID(channel);
                    Color observed=block.HasColor(id) ? block.GetColor(id) : slot.original.GetColor(id);
                    if(!slot.written.TryGetValue(channel,out var last) || observed!=last)slot.bases[channel]=observed;
                    Color value=GradeColor(slot.bases[channel],tone);
                    block.SetColor(id,value);slot.written[channel]=value;
                }
                if(slot.written.Count>0)slot.renderer.SetPropertyBlock(block,slot.index);
                if(slot.resetting && slot.current.Values.All(x=>(x-Neutral).sqrMagnitude<1e-8f)) {Restore(slot);restored=true;}
            }
            if(restored)OnResetSettled?.Invoke();
        }
        public static Color GradeColor(Color c,Vector4 tone)
        {
            if((tone-Neutral).sqrMagnitude<1e-10f)return c;
            Color.RGBToHSV(c,out float h,out float s,out float v);
            if(s<.001f && tone.w>.001f)h=0;
            var rgb=Color.HSVToRGB(Mathf.Repeat(h+tone.x,1),Mathf.Clamp01(s*tone.y+tone.w*(1-s)),v*Mathf.Pow(2,tone.z),true);
            rgb.a=c.a;return rgb;
        }
        void RestoreColors(Slot slot)
        {
            if(!slot.renderer)return;
            slot.renderer.GetPropertyBlock(block,slot.index);
            foreach(var pair in slot.written)
            {
                int id=Shader.PropertyToID(pair.Key);
                // Preserve a new externally-written animation value on reset.
                if(block.HasColor(id) && block.GetColor(id)==pair.Value && slot.bases.TryGetValue(pair.Key,out var color))block.SetColor(id,color);
            }
            slot.renderer.SetPropertyBlock(block,slot.index);
        }
        void Restore(Slot slot)
        {
            if(slot.clone && slot.renderer)
            {
                RestoreColors(slot);var materials=slot.renderer.sharedMaterials;
                if(slot.index<materials.Length && materials[slot.index]==slot.clone) {materials[slot.index]=slot.original;slot.renderer.sharedMaterials=materials;}
                DestroyMaterial(slot.clone);
            }
            slot.clone=null;slot.resetting=false;slot.target.Clear();slot.current.Clear();slot.bases.Clear();slot.written.Clear();
        }
        public void Reset(string component,bool immediate=false)
        {
            void ResetOne(Slot slot) {
                if(immediate || !slot.clone) {Restore(slot);return;}
                foreach(var channel in slot.target.Keys.ToArray())slot.target[channel]=Neutral;
                slot.resetting=true;
            }
            if(string.IsNullOrEmpty(component)) {foreach(var slot in slots.Values)ResetOne(slot);return;}
            if(slots.TryGetValue(component,out var one))ResetOne(one);
            else throw new ArgumentException("Unknown palette component");
        }
        static void DestroyMaterial(Material material)
        {if(Application.isPlaying)Destroy(material);else DestroyImmediate(material);}
        void OnDestroy() {foreach(var slot in slots.Values)Restore(slot);}
    }
}
