using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

// Tda Hatsune Miku Append, edited by monjo3456; project adaptation and original gestures.
// Original terms and credits are preserved beside the source and in the App.
public static class MikuCharacterBuilder
{
    const string Folder="Assets/MikuCharacter";
    const string Source=Folder+"/Source";
    static readonly string[] Actions={"Wave","Jump","Dance","Bow","Spin","Greet","Cheer","No"};
    static GameObject root;
    static Transform rig;
    static Transform[] bones;
    static readonly Dictionary<string,Transform> named=new();
    static readonly Dictionary<string,string> aliases=new();
    static PmxModelData data;
    static SkinnedMeshRenderer face;

    public static GameObject Create()
    {
        data=PmxModelData.Load(Directory.GetFiles(Source,"*.pmx").Single());
        Directory.CreateDirectory(Folder+"/Adapted");AssetDatabase.Refresh();
        root=new GameObject("HatsuneMiku");rig=new GameObject("Rig").transform;rig.SetParent(root.transform,false);
        named.Clear();aliases.Clear();bones=new Transform[data.bones.Length];
        for(int i=0;i<bones.Length;i++)
        {
            var b=data.bones[i];var t=new GameObject(b.name).transform;t.SetParent(rig,false);t.position=b.position;bones[i]=t;named[b.name]=t;
        }
        for(int i=0;i<bones.Length;i++)
            if(data.bones[i].parent>=0)bones[i].SetParent(bones[data.bones[i].parent],true);
        aliases["全ての親"]="Root";aliases["上半身"]="Body";aliases["頭"]="HeadPivot";
        for(int s=0;s<2;s++)
        {
            string jp=s==0?"左":"右",en=s==0?"Left":"Right";
            aliases[jp+"腕"]="Arm"+en;aliases[jp+"ひじ"]="Forearm"+en;aliases[jp+"手首"]="Hand"+en;
            aliases[jp+"足D"]="Leg"+en;aliases[jp+"ひざD"]="Shin"+en;
            for(int j=1;j<=8;j++)aliases[jp+"髪"+(char)('０'+j)]="Hair"+j+en;
            for(int j=1;j<=3;j++)foreach(string finger in new[]{"親指","人指","中指","薬指","小指"})
                if(named.ContainsKey(jp+finger+(char)('０'+j)))aliases[jp+finger+(char)('０'+j)]="Finger"+finger+j+en;
        }
        aliases["ﾈｸﾀｲ１"]="Tie";
        // Compact per-renderer vertices; exact face geometry remains available for head taps.
        var headIndices=new[]{0,1,2,3,14};
        face=CreateRenderer("Head",headIndices);
        var body=CreateRenderer("BodyMesh",new[]{4,5,6,7,8,9,10,11,12,16});
        var character=root.AddComponent<ViewerCharacter>();character.modelId="hatsune-miku";character.displayName="初音未来";character.portraitFramingScale=.70f;character.actions=Actions;
        root.AddComponent<MikuSecondaryMotion>();
        var player=root.AddComponent<Animation>();
        foreach(string action in new[]{"Idle"}.Concat(Actions))
        {
            var clip=MikuMotionBuilder.Build(root,action);string path=Folder+"/Adapted/"+action+".anim";Save(clip,path);
            player.AddClip(AssetDatabase.LoadAssetAtPath<AnimationClip>(path),action);
        }
        player.clip=player.GetClip("Idle");player.playAutomatically=false;player.enabled=false;
        // Match the neutral mesh to the authored relaxed pose for reliable camera fitting.
        // Bounds include the A-pose width, keeping all arm gestures in view without camera pumping.
        string report=Path.GetFullPath("../../.local/checks/miku-geometry.json");
        File.WriteAllText(report,"{\"model\":\"Tda Hatsune Miku Append / monjo3456\",\"vertices\":"+(face.sharedMesh.vertexCount+body.sharedMesh.vertexCount)+",\"triangles\":"+((face.sharedMesh.triangles.Length+body.sharedMesh.triangles.Length)/3)+",\"renderers\":2,\"materialSlots\":15,\"bones\":"+bones.Length+",\"sdefConvertedToLinear\":"+data.sdefVertices+"}");
        var result=root;root=null;rig=null;bones=null;data=null;face=null;named.Clear();aliases.Clear();return result;
    }
    static SkinnedMeshRenderer CreateRenderer(string name,int[] surfaceIndices)
    {
        var originalIndices=surfaceIndices.SelectMany(s=>data.indices.Skip(data.surfaces[s].start).Take(data.surfaces[s].count)).Distinct().OrderBy(i=>i).ToArray();
        var remap=originalIndices.Select((v,i)=>(v,i)).ToDictionary(p=>p.v,p=>p.i);
        var mesh=new Mesh{name=name,indexFormat=IndexFormat.UInt32};
        mesh.vertices=originalIndices.Select(i=>data.vertices[i]).ToArray();mesh.normals=originalIndices.Select(i=>data.normals[i]).ToArray();
        mesh.uv=originalIndices.Select(i=>data.uv[i]).ToArray();mesh.boneWeights=originalIndices.Select(i=>data.weights[i]).ToArray();
        mesh.bindposes=bones.Select(t=>t.worldToLocalMatrix*root.transform.localToWorldMatrix).ToArray();mesh.subMeshCount=surfaceIndices.Length;
        for(int i=0;i<surfaceIndices.Length;i++)
        {
            var s=data.surfaces[surfaceIndices[i]];
            mesh.SetTriangles(data.indices.Skip(s.start).Take(s.count).Select(v=>remap[v]).ToArray(),i);
        }
        // Keep only the facial expressions used by this App, rather than all 70 MMD controls.
        if(name=="Head")foreach(var pair in new[]{("まばたき","Blink"),("口角上げ","Smile"),("あ","OpenMouth")})
        {
            var morph=data.morphs.Single(m=>m.name==pair.Item1);var deltas=new Vector3[originalIndices.Length];
            for(int i=0;i<originalIndices.Length;i++)if(morph.offsets.TryGetValue(originalIndices[i],out var v))deltas[i]=v;
            mesh.AddBlendShapeFrame(pair.Item2,100,deltas,null,null);
        }
        mesh.RecalculateTangents();mesh.RecalculateBounds();string path=Folder+"/Adapted/"+name+".asset";Save(mesh,path);
        var renderer=new GameObject(name).AddComponent<SkinnedMeshRenderer>();renderer.transform.SetParent(root.transform,false);
        renderer.sharedMesh=AssetDatabase.LoadAssetAtPath<Mesh>(path);renderer.bones=bones;renderer.rootBone=rig;
        renderer.sharedMaterials=surfaceIndices.Select(i=>Material(data.surfaces[i])).ToArray();
        renderer.quality=SkinQuality.Bone4;renderer.updateWhenOffscreen=false;
        renderer.localBounds=new Bounds(new Vector3(0,3,0),new Vector3(8,9,6));
        renderer.shadowCastingMode=ShadowCastingMode.On;renderer.receiveShadows=true;return renderer;
    }
    static Material Material(PmxModelData.Surface surface)
    {
        string path=Folder+"/Adapted/"+surface.name+".mat";
        var m=AssetDatabase.LoadAssetAtPath<Material>(path);
        if(!m){m=new Material(Shader.Find("Universal Render Pipeline/Lit"));AssetDatabase.CreateAsset(m,path);}
        m.shader=Shader.Find("Universal Render Pipeline/Lit");m.shaderKeywords=Array.Empty<string>();
        bool skin=surface.name.StartsWith("face")||surface.name=="skin";
        bool glow=surface.name.Contains("green")||surface.name=="wing"||surface.name=="body_pink";
        bool hair=surface.name.StartsWith("hair");
        var color=Color.white;
        if(glow)color=surface.name=="body_pink"?new Color(.85f,.1f,.35f):new Color(.16f,.85f,.69f);
        m.SetColor("_BaseColor",color);m.SetFloat("_Cull",0);m.SetFloat("_Surface",0);m.SetFloat("_Blend",0);
        m.SetFloat("_SrcBlend",1);m.SetFloat("_DstBlend",0);m.SetFloat("_ZWrite",1);
        m.SetFloat("_AlphaClip",1);m.SetFloat("_Cutoff",.45f);m.EnableKeyword("_ALPHATEST_ON");m.SetFloat("_AlphaToMask",1);
        m.renderQueue=(int)RenderQueue.AlphaTest;m.SetOverrideTag("RenderType","TransparentCutout");
        m.SetFloat("_Metallic",skin?0:hair?.02f:glow?.18f:.38f);
        m.SetFloat("_Smoothness",skin?.22f:hair?.30f:glow?.50f:.45f);
        if(surface.texture!=null)
        {
            string texturePath=Source+"/"+surface.texture;
            var importer=(TextureImporter)AssetImporter.GetAtPath(texturePath);
            if(!importer)throw new Exception("Missing model texture: "+texturePath);
            if(importer.maxTextureSize!=4096||importer.GetPlatformTextureSettings("iPhone").format!=TextureImporterFormat.ASTC_4x4)
            {
                importer.maxTextureSize=4096;importer.mipmapEnabled=true;importer.sRGBTexture=true;importer.alphaSource=TextureImporterAlphaSource.FromInput;
                importer.alphaIsTransparency=true;importer.filterMode=FilterMode.Trilinear;importer.anisoLevel=8;
                importer.SetPlatformTextureSettings(new TextureImporterPlatformSettings{name="iPhone",overridden=true,maxTextureSize=4096,format=TextureImporterFormat.ASTC_4x4,compressionQuality=100});
                importer.SaveAndReimport();
            }
            var texture=AssetDatabase.LoadAssetAtPath<Texture2D>(texturePath);m.SetTexture("_BaseMap",texture);
            // A small albedo fill protects anime facial lines from harsh studio specular contrast.
            if(skin||glow){m.EnableKeyword("_EMISSION");m.SetTexture("_EmissionMap",texture);m.SetColor("_EmissionColor",color*(skin?.13f:.26f));}
        }
        if(surface.name.StartsWith("face") || surface.name.StartsWith("eye") || surface.name=="cheek")
        { m.shader=Shader.Find("ModelSpace/SoftPortrait"); m.shaderKeywords=Array.Empty<string>(); }
        EditorUtility.SetDirty(m);return m;
    }
    static void Save(UnityEngine.Object value,string path)
    {
        var existing=AssetDatabase.LoadMainAssetAtPath(path);
        if(existing){EditorUtility.CopySerialized(value,existing);UnityEngine.Object.DestroyImmediate(value);EditorUtility.SetDirty(existing);}
        else AssetDatabase.CreateAsset(value,path);
    }
}
