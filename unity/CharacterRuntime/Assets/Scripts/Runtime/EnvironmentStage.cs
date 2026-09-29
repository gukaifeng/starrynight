using System;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class EnvironmentDisplay { public string name, description, category, thumbnail; public int order; }
    [Serializable] public sealed class EnvironmentSource { public string kind, model; public float scale=1,yaw; }
    [Serializable] public sealed class EnvironmentClearance { public float referenceHeight=1.7f,clearRadius=1.2f; }
    [Serializable] public sealed class EnvironmentLighting
    {
        public string sky="#B3D1D6",ambient="#888F91",key="#FFF3E3",fill="#DDEBFF";
        public float keyIntensity=1.5f,fillIntensity=.32f,rimIntensity=.48f;
    }
    [Serializable] public sealed class EnvironmentPalette { public string id,name,surface,accent; }
    [Serializable] public sealed class EnvironmentBindings { public string[] surface=Array.Empty<string>(),accent=Array.Empty<string>(),decor=Array.Empty<string>(); }
    [Serializable] public sealed class EnvironmentManifest
    {
        public int schemaVersion=1; public string id,packageId,packageVersion;
        public EnvironmentDisplay display; public EnvironmentSource source; public EnvironmentClearance stage;
        public EnvironmentLighting lighting; public EnvironmentPalette[] palettes; public EnvironmentBindings bindings;
    }
    [Serializable] public sealed class EnvironmentSettings
    {
        public string palette="original"; public bool decorations=true; public float angle;
    }
    [Serializable] public sealed class EnvironmentState
    {
        public int apiMajor=1; public string selectedId,visibleId,palette;
        public bool decorations,transitioning; public float angle,transitionOpacity,keyAngle,keyHeight;
        public int ambientNodes,rendererCount,vertexCount;
        public bool ambientRunning,motionSuppressed;
        public float ambientTime,clothOffset,swayDegrees;
    }
    // A scene's geometry and controls have no dependency on any character rig.
    public sealed class EnvironmentStage : MonoBehaviour
    {
        public TextAsset manifestAsset;
        public Transform geometry;
        EnvironmentManifest manifest;
        public EnvironmentManifest Manifest => manifest ?? (manifest=JsonUtility.FromJson<EnvironmentManifest>(manifestAsset.text));
        sealed class Paint { public Renderer renderer; public int slot,property; public Color current; public bool accent; public MaterialPropertyBlock block=new MaterialPropertyBlock(); }
        Paint[] paint=Array.Empty<Paint>(); Transform[] decorations=Array.Empty<Transform>();
        string paletteId; float angle; bool bound;
        public EnvironmentAmbientMotion Ambient { get; private set; }
        public static Color ColorValue(string html) => ColorUtility.TryParseHtmlString(html,out var value) ? value : Color.white;
        public void Initialize()
        {
            if(bound) return;
            bound=true;
            Ambient=geometry.GetComponent<EnvironmentAmbientMotion>();
            if(Application.isPlaying && Ambient) Ambient.Initialize();
            var all=new System.Collections.Generic.List<Paint>();
            void Bind(string[] paths,bool accent)
            {
                foreach(string path in paths)
                {
                    var root=geometry.Find(path); if(!root) continue;
                    foreach(var renderer in root.GetComponentsInChildren<Renderer>(true))
                    {
                        var materials=renderer.sharedMaterials;
                        for(int i=0;i<materials.Length;i++)
                        {
                            var mat=materials[i];string field=CharacterContract.ColorProperty(mat,"baseColor");
                            if(mat.HasProperty(field)) all.Add(new Paint {renderer=renderer,slot=i,property=Shader.PropertyToID(field),current=mat.GetColor(field),accent=accent});
                        }
                    }
                }
            }
            Bind(Manifest.bindings.surface,false);Bind(Manifest.bindings.accent,true);paint=all.ToArray();
            decorations=Array.ConvertAll(Manifest.bindings.decor,p=>geometry.Find(p));
        }
        public void SetDecorations(bool enabled) { Initialize();foreach(var item in decorations) if(item) item.gameObject.SetActive(enabled); }
        public void Apply(EnvironmentSettings settings,float dt,bool instant=false)
        {
            Initialize();EnvironmentPalette palette=Array.Find(Manifest.palettes,p=>p.id==settings.palette) ?? Manifest.palettes[0];
            paletteId=palette.id;float t=instant ? 1 : 1-Mathf.Exp(-dt*6);
            Color surface=ColorValue(palette.surface),accent=ColorValue(palette.accent);
            foreach(var p in paint)
            {
                Color target=p.accent ? accent : surface;
                if(!instant && ((Vector4)(p.current-target)).sqrMagnitude<0.00000001f) continue;
                p.current=Color.Lerp(p.current,target,t);
                p.renderer.GetPropertyBlock(p.block,p.slot);p.block.SetColor(p.property,p.current);p.renderer.SetPropertyBlock(p.block,p.slot);
            }
            angle=Mathf.Lerp(angle,StudioSettings.Safe(settings.angle,-25,25,0),t);
            transform.localRotation=Quaternion.Euler(0,angle,0);
        }
        public string Palette => paletteId;
        public float Angle => angle;
    }
}
