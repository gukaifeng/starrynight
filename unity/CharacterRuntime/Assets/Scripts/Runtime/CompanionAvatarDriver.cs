using System;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    // LateUpdate follows the baked animation, before gaze and hair. Speech is audio amplitude,
    // not phoneme inference; only explicitly configured render properties are changed.
    [DefaultExecutionOrder(50)]
    public sealed class CompanionAvatarDriver : MonoBehaviour
    {
        public CharacterPerformanceDriver Performance { get; set; }
        public const int AtmosphereRevision = 1;
        struct AccentSlot { public Renderer renderer; public int index; public Color original; public bool light; }
        readonly List<AccentSlot> accents = new List<AccentSlot>();
        MaterialPropertyBlock block;
        readonly List<SpeechShape> speechShapes=new List<SpeechShape>();
        struct SpeechShape { public SkinnedMeshRenderer skin; public int index; public float weight,scale; public string viseme; }
        readonly Dictionary<string,float> visemes=new Dictionary<string,float>();
        float lastAudioTime=-1;
        Transform head;
        Quaternion headBeforeAccent;
        bool headAccentApplied,proceduralHeadMotion=true;
        
        float targetMouth, mouth;
        string state = "idle";
        bool companion;
        AvatarControlDriver authored;
        Color tint = Color.white;
        Light[] lights;
        Color[] originalLightColors;
        Color originalBackground;
        Camera camera;
        Renderer ground;
        public void Bind(Transform character, Camera view)
        {
            RestorePose();
            head = null; targetMouth = mouth = 0; state = "idle"; speechShapes.Clear(); visemes.Clear(); lastAudioTime=-1;
            accents.Clear(); camera = view;
            ground = GameObject.Find("Ground")?.GetComponent<Renderer>();
            block = new MaterialPropertyBlock();
            if (lights == null)
            {
                lights = FindObjectsByType<Light>(FindObjectsSortMode.None);
                originalLightColors = new Color[lights.Length];
                for (int i = 0; i < lights.Length; i++) originalLightColors[i] = lights[i].color;
                originalBackground = camera.backgroundColor;
            }
            var manifest=character.GetComponent<ViewerCharacter>().Manifest;
            authored=character.GetComponent<AvatarControlDriver>();
            head=CharacterContract.Resolve(character,manifest.rig.head);
            proceduralHeadMotion=manifest.speech.proceduralHeadMotion;
            void Add(ShapeBinding binding,string id)
            {
                var skin=CharacterContract.Resolve(character,binding.renderer)?.GetComponent<SkinnedMeshRenderer>();
                int index=skin ? skin.sharedMesh.GetBlendShapeIndex(binding.shape) : -1;
                if(index>=0) speechShapes.Add(new SpeechShape { skin=skin,index=index,weight=binding.weight,scale=CharacterContract.MorphScale(skin,index),viseme=id });
            }
            foreach(var binding in manifest.speech.amplitude) Add(binding,"");
            foreach(var v in manifest.speech.visemes) foreach(var binding in v.bindings) Add(binding,v.id);
            // Built-in accent colors are a legacy authoring adapter; external packages own explicit parameters.
            if(manifest.source.format!="builtin") return;
            foreach (var renderer in character.GetComponentsInChildren<Renderer>())
            {
                var materials = renderer.sharedMaterials;
                for (int i = 0; i < materials.Length; i++)
                {
                    var material = materials[i];
                    if (!material || !material.HasProperty("_BaseColor")) continue;
                    if (material.name.StartsWith("hair",StringComparison.OrdinalIgnoreCase) || material.name.StartsWith("Enamel") || material.name.StartsWith("Light"))
                        accents.Add(new AccentSlot { renderer = renderer, index = i, original = material.GetColor("_BaseColor"), light = material.name.StartsWith("Light") });
                }
            }
        }
        public void Configure(string accent, string ambience)
        {
            if (block == null) block = new MaterialPropertyBlock();
            tint = accent == "鸢紫" ? new Color(.83f,.58f,1f) : accent == "暖金" ? new Color(1f,.76f,.38f) : Color.white;
            foreach (var slot in accents)
            {
                slot.renderer.GetPropertyBlock(block,slot.index);
                block.SetColor("_BaseColor", tint == Color.white ? slot.original : Color.Lerp(slot.original,tint,.72f));
                if (slot.light) block.SetColor("_EmissionColor",(tint == Color.white ? new Color(.2f,.85f,1f) : tint)*1.3f);
                slot.renderer.SetPropertyBlock(block,slot.index); block.Clear();
            }
            var lightTint = ambience == "暖暮" ? new Color(1f,.86f,.7f) : ambience == "月色" ? new Color(.72f,.83f,1f) : Color.white;
            for (int i = 0; i < lights.Length; i++) if (lights[i]) lights[i].color = originalLightColors[i] * lightTint;
            var room = ambience == "暖暮" ? new Color(.91f,.81f,.70f)
                : ambience == "月色" ? new Color(.69f,.77f,.85f) : new Color(.80f,.87f,.80f);
            camera.backgroundColor = room;
            RenderSettings.fogColor = room;
            if (ground)
            {
                ground.GetPropertyBlock(block);
                block.SetColor("_BaseColor", ambience == "暖暮" ? new Color(.78f,.67f,.52f)
                    : ambience == "月色" ? new Color(.48f,.58f,.69f) : new Color(.65f,.75f,.61f));
                ground.SetPropertyBlock(block); block.Clear();
            }
        }
        public void SetEnabled(bool value) { companion = value; SetState("idle"); SetMouth(0); }
        public void SetState(string value) { state = value; if (value != "speaking") { targetMouth = 0; visemes.Clear(); lastAudioTime=-1; } }
        public bool SetSpeech(float time,float level,VisemeValue[] values)
        {
            if(time<lastAudioTime) return false;
            lastAudioTime=time; SetMouth(level); visemes.Clear();
            foreach(var value in values ?? Array.Empty<VisemeValue>()) visemes[value.id]=Mathf.Clamp01(value.weight);
            return true;
        }
        public void SetMouth(float value) { targetMouth = Mathf.Clamp01(value); }
        // Called after gaze restoration and before rebinding an actor, so its
        // final speech accent cannot be left behind on an inactive character.
        public void RestorePose()
        {
            if(headAccentApplied && head)head.localRotation=headBeforeAccent;
            headAccentApplied=false;
        }
        void LateUpdate() { Step(Time.unscaledDeltaTime,Time.unscaledTime); }
        public void Step(float dt,float clock)
        {
            mouth = Mathf.Lerp(mouth,companion ? targetMouth : 0,1-Mathf.Exp(-22*dt));
            for(int i=0;i<speechShapes.Count;i++)
            {
                if(authored && !authored.AllowSpeech)continue;
                var binding=speechShapes[i]; bool first=true;
                for(int j=0;j<i;j++) if(speechShapes[j].skin==binding.skin && speechShapes[j].index==binding.index) { first=false; break; }
                if(!first) continue;
                float target=0;
                for(int j=i;j<speechShapes.Count;j++)
                {
                    var b=speechShapes[j]; if(b.skin!=binding.skin || b.index!=binding.index) continue;
                    float weight=string.IsNullOrEmpty(b.viseme) ? (visemes.Count==0?mouth:0) : visemes.TryGetValue(b.viseme,out var v) ? v : 0;
                    target+=weight*b.weight;
                }
                float value=Mathf.Lerp(binding.skin.GetBlendShapeWeight(binding.index),companion?Mathf.Clamp01(target)*binding.scale:0,1-Mathf.Exp(-22*dt));
                binding.skin.SetBlendShapeWeight(binding.index,value);
            }
            headAccentApplied=false;
            if (proceduralHeadMotion && companion && head && state != "idle")
            {
                headBeforeAccent=head.localRotation;headAccentApplied=true;
                float amplitude = state == "listening" ? 1.8f : state == "thinking" ? .7f : 1.2f;
                head.localRotation *= Quaternion.Euler(Mathf.Sin(clock*2.1f)*amplitude*(Performance?Performance.GazeWeight:1),0,0);
            }
            if (!companion) return;
            foreach (var slot in accents)
            {
                if (!slot.light) continue;
                slot.renderer.GetPropertyBlock(block,slot.index);
                block.SetColor("_EmissionColor",(tint == Color.white ? new Color(.2f,.85f,1f) : tint)*(1.3f+mouth*1.5f));
                slot.renderer.SetPropertyBlock(block,slot.index); block.Clear();
            }
        }
    }
}
