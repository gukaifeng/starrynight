using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using UnityEditor;
using UnityEngine;
using ModelSpace;

// This is the only engine-specific packaging boundary. Authoring packages contain data,
// while the player receives compiled assets built for its Unity version and platform.
public static class CharacterPackageBuilder
{
    public static string Root => Path.GetFullPath(Path.Combine(Application.dataPath,"../../.."));
    [Serializable] public class ActiveRoster { public int schemaVersion; public string defaultCharacter; public string[] characters; }
    public static ActiveRoster Roster => JsonUtility.FromJson<ActiveRoster>(File.ReadAllText(Path.Combine(Root,"assets/characters/active-roster.json")));
    public static void Preflight()
    {
        string python=Path.Combine(Root,".local/character-sdk-venv/bin/python");
        if(!File.Exists(python)) throw new Exception("Install the character SDK venv before exporting (see character-sdk/README.md)");
        var info=new System.Diagnostics.ProcessStartInfo(python,"\""+Path.Combine(Root,"scripts/validate_characters.py")+"\"") {
            UseShellExecute=false,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=Root };
        using(var process=System.Diagnostics.Process.Start(info))
        {
            string output=process.StandardOutput.ReadToEnd(),error=process.StandardError.ReadToEnd(); process.WaitForExit();
            if(process.ExitCode!=0) throw new Exception("CHARACTER_PREFLIGHT_FAILED: "+error+output);
        }
    }
    public static void AttachBuiltin(ViewerCharacter character)
    {
        string id=character.modelId;
        string destination="Assets/CharacterPackages/Builtin/"+id+".json";
        Directory.CreateDirectory(Path.GetDirectoryName(destination));
        File.Copy(Path.Combine(Root,"character-packages/builtins",id,"character.json"),destination,true);
        AssetDatabase.ImportAsset(destination,ImportAssetOptions.ForceSynchronousImport);
        character.contractAsset=AssetDatabase.LoadAssetAtPath<TextAsset>(destination);
        character.ApplyContract(); ValidateBindings(character);
    }
    public static List<ViewerCharacter> CreateImported()
    {
        var output=new List<ViewerCharacter>();
        var directory=Path.Combine(Root,"character-packages/imported");
        if(!Directory.Exists(directory)) return output;
        foreach(var source in Directory.GetDirectories(directory).OrderBy(p=>p,StringComparer.Ordinal))
        {
            var json=File.ReadAllText(Path.Combine(source,"character.json"));
            var manifest=JsonUtility.FromJson<CharacterManifest>(json); CharacterContract.Validate(manifest);
            if(!Roster.characters.Contains(manifest.id))continue;
            string folder="Assets/CharacterPackages/Imported/"+manifest.id;
            Directory.CreateDirectory(folder);
            foreach(string file in Directory.GetFiles(source,"*",SearchOption.AllDirectories))
            {
                string relative=file.Substring(source.Length+1),target=Path.Combine(folder,relative);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                if(!File.Exists(target) || Hash(file)!=Hash(target)) File.Copy(file,target,true);
            }
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            string modelPath=folder+"/"+manifest.source.model;
            var importer=AssetImporter.GetAtPath(modelPath);
            if(!importer || !importer.GetType().FullName.Contains("GltfImporter")) throw new Exception("CHARACTER_GLTF_IMPORTER_MISSING");
            var settings=new SerializedObject(importer);
            var animation=settings.FindProperty("importSettings.animationMethod");
            if(animation==null) throw new Exception("CHARACTER_GLTF_SETTINGS_MISSING");
            // enum: None=0, Legacy=1, Mecanim=2 (read from installed importer enum, not a guessed index).
            int legacy=Array.IndexOf(animation.enumNames,"Legacy");
            if(legacy<0) throw new Exception("CHARACTER_GLTF_LEGACY_UNAVAILABLE");
            if(animation.enumValueIndex!=legacy) { animation.enumValueIndex=legacy; settings.ApplyModifiedPropertiesWithoutUndo(); importer.SaveAndReimport(); }
            var asset=AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
            if(!asset) throw new Exception("CHARACTER_MODEL_IMPORT_FAILED: "+manifest.id);
            var model=UnityEngine.Object.Instantiate(asset); model.name=manifest.id;
            model.transform.localScale=Vector3.one*manifest.source.scale;
            model.transform.rotation=Quaternion.Euler(0,manifest.source.yaw,0);
            foreach(var animator in model.GetComponentsInChildren<Animator>(true)) UnityEngine.Object.DestroyImmediate(animator);
            foreach(var old in model.GetComponentsInChildren<Animation>(true)) UnityEngine.Object.DestroyImmediate(old);
            var player=model.AddComponent<Animation>(); player.playAutomatically=false; player.enabled=false;
            var clips=AssetDatabase.LoadAllAssetsAtPath(modelPath).OfType<AnimationClip>().ToArray();
            foreach(var action in manifest.actions)
            {
                var clip=clips.FirstOrDefault(c=>c.name==action.clip);
                if(!clip || !clip.legacy) throw new Exception("CHARACTER_CLIP_MISSING: "+action.clip);
                player.AddClip(clip,action.id);
            }
            if(manifest.posture!=null) foreach(string name in manifest.posture.Clips)
            {
                var clip=clips.FirstOrDefault(c=>c.name==name);
                if(!clip || !clip.legacy)throw new Exception("POSTURE_CLIP_MISSING: "+name);
                player.AddClip(clip,name);
            }
            player.clip=player.GetClip("Idle"); player.GetClip("Idle").SampleAnimation(model,0);
            var character=model.AddComponent<ViewerCharacter>();
            character.contractAsset=AssetDatabase.LoadAssetAtPath<TextAsset>(folder+"/character.json"); character.ApplyContract();
            CharacterPerformanceBuilder.Prepare(character,clips);
            var breath=manifest.autonomy?.breathing;
            if(manifest.Supports("core.autonomy@1") && !string.IsNullOrEmpty(breath?.clip))
            {
                var clip=clips.FirstOrDefault(c=>c.name==breath.clip);
                if(!clip || !clip.legacy)throw new Exception("AUTONOMY_BREATH_MISSING: "+breath.clip);
                player.AddClip(clip,breath.clip);
            }
            ValidateBindings(character);
            AnimeCharacterAdapter.Prepare(character,folder);
            if(manifest.Supports("core.avatar-controls@1"))PortableAvatarControllerBuilder.Prepare(character.gameObject,folder,player.GetClip("Idle"));
            var bounds=character.RestBounds(); character.transform.position=new Vector3(-bounds.center.x,-bounds.min.y,-bounds.center.z);
            FramingReview.BakeCharacter(character);
            CharacterPortraitCalibrationBuilder.Prepare(character);
            PostureGroundingBuilder.Build(character);
            float restSize=character.RestBounds().size.magnitude;
            foreach(var envelope in character.framingEnvelopes)
                if(character.FramingBounds(envelope.action).size.magnitude>restSize*6)
                    throw new Exception("CHARACTER_ACTION_BOUNDS_EXCESSIVE: "+manifest.id+"/"+envelope.action);
            PrefabUtility.SaveAsPrefabAssetAndConnect(model,"Assets/Prefabs/Package_"+manifest.id+".prefab",InteractionMode.AutomatedAction);
            model.SetActive(false); output.Add(character);
        }
        return output;
    }
    public static void ValidateBindings(ViewerCharacter character)
    {
        var m=character.Manifest; var root=character.transform;
        Transform Resolve(string path) { var t=CharacterContract.Resolve(root,path); if(!t) throw new Exception("CHARACTER_PATH_MISSING: "+m.id+"/"+path); return t; }
        Resolve(m.rig.head);
        if(!Resolve(m.rig.headRenderer).GetComponent<Renderer>()) throw new Exception("CHARACTER_HEAD_RENDERER_MISSING");
        if(!string.IsNullOrEmpty(m.rig.neck)) Resolve(m.rig.neck);
        if(!string.IsNullOrEmpty(m.rig.leftEye)) { Resolve(m.rig.leftEye); Resolve(m.rig.rightEye); }
        void Shape(ShapeBinding b)
        {
            var skin=Resolve(b.renderer).GetComponent<SkinnedMeshRenderer>();
            if(!skin || skin.sharedMesh.GetBlendShapeIndex(b.shape)<0) throw new Exception("CHARACTER_MORPH_MISSING: "+b.renderer+"/"+b.shape);
        }
        foreach(var e in m.expressions) foreach(var b in e.bindings) Shape(b);
        foreach(var b in m.speech.amplitude) Shape(b);
        foreach(var v in m.speech.visemes) foreach(var b in v.bindings) Shape(b);
        if(CharacterAutonomyContract.Supported(m))
        {
            foreach(var b in m.autonomy.blink.bindings)Shape(b);
            if(m.autonomy.breathing?.bones!=null)foreach(var path in m.autonomy.breathing.bones)Resolve(path);
        }
        foreach(var p in m.parameters) foreach(var b in p.bindings)
        {
            var t=Resolve(b.path);
            if(p.kind=="morph") { Shape(new ShapeBinding { renderer=b.path,shape=b.property }); if(!string.IsNullOrEmpty(b.negativeShape)) Shape(new ShapeBinding { renderer=b.path,shape=b.negativeShape }); }
            if(p.kind=="variant")
            {
                var protectedPaths=new[]{m.rig.head,m.rig.neck,m.rig.leftEye,m.rig.rightEye,m.rig.headRenderer}
                    .Concat(m.expressions.SelectMany(e=>e.bindings.Select(x=>x.renderer)))
                    .Concat(m.speech.amplitude.Select(x=>x.renderer)).Concat(m.speech.visemes.SelectMany(v=>v.bindings.Select(x=>x.renderer)));
                if(protectedPaths.Where(x=>!string.IsNullOrEmpty(x)).Any(x=>Resolve(x)==t || Resolve(x).IsChildOf(t)))
                    throw new Exception("CHARACTER_VARIANT_HIDES_REQUIRED_RIG: "+b.path);
            }
            if(p.kind=="color")
            {
                var renderer=t.GetComponent<Renderer>();
                if(!renderer || b.materialSlot>=renderer.sharedMaterials.Length || !renderer.sharedMaterials[b.materialSlot].HasProperty(CharacterContract.ColorProperty(renderer.sharedMaterials[b.materialSlot],b.property)))
                    throw new Exception("CHARACTER_MATERIAL_BINDING_INVALID: "+b.path+"/"+b.property);
            }
        }
        foreach(var region in m.interactions) { Resolve(region.bone); if(!string.IsNullOrEmpty(region.renderer)) Resolve(region.renderer); }
        CharacterPerformanceBuilder.Validate(character);
        if(m.posture!=null && m.posture.poses.Length>0)
        {
            foreach(string bone in m.posture.bones) Resolve(bone);
            var player=character.GetComponentInChildren<Animation>(true);
            foreach(string name in m.posture.Clips)
            {
                var clip=player.GetClip(name);if(!clip)throw new Exception("POSTURE_CLIP_MISSING: "+name);
                var bindings=AnimationUtility.GetCurveBindings(clip);
                foreach(string bone in m.posture.bones)
                    foreach(string property in new[]{"localPosition.x","localPosition.y","localPosition.z","localRotation.x","localRotation.y","localRotation.z","localRotation.w"})
                        if(!bindings.Any(b=>b.path==bone && string.Equals(b.propertyName.Replace("m_",""),property,StringComparison.OrdinalIgnoreCase)))throw new Exception("POSTURE_INCOMPLETE_TRACK: "+name+"/"+bone+"/"+property);
            }
        }
    }
    [Serializable] sealed class Catalog { public int schemaVersion=1,apiMajor=1,apiMinor=1; public CharacterManifest[] characters; }
    public static void CatalogForHost(ViewerCharacter[] characters)
    {
        var catalog=new Catalog { characters=characters.Select(c=>c.Manifest).OrderBy(c=>c.display.order).ThenBy(c=>c.id,StringComparer.Ordinal).ToArray() };
        if(catalog.characters.Select(c=>c.id).Distinct().Count()!=characters.Length) throw new Exception("CHARACTER_DUPLICATE_ID");
        File.WriteAllText(Path.Combine(Root,"ios/CharacterHost/Resources/CharacterCatalog.json"),JsonUtility.ToJson(catalog,true)+"\n");
    }
    public static string CatalogHash => Hash(Path.Combine(Root,"ios/CharacterHost/Resources/CharacterCatalog.json"));
    static string Hash(string path) { using(var sha=SHA256.Create()) return string.Concat(sha.ComputeHash(File.ReadAllBytes(path)).Select(b=>b.ToString("x2"))); }
    public static void PrepareEffects()
    {
        string folder="Assets/Resources/CharacterPlatform"; Directory.CreateDirectory(folder);
        foreach(string name in new[]{"Star","Heart"})
        {
            var texture=new Texture2D(64,64,TextureFormat.RGBA32,false);
            for(int y=0;y<64;y++) for(int x=0;x<64;x++)
            {
                float u=(x-31.5f)/29,v=(y-31.5f)/29;
                float shape=name=="Heart" ? Mathf.Pow(u*u+v*v-0.7f,3)-u*u*v*v*v : Mathf.Abs(u)*Mathf.Abs(v)*10+Mathf.Sqrt(u*u+v*v)-.9f;
                float alpha=1-Mathf.SmoothStep(0,1,Mathf.InverseLerp(-.03f,.025f,shape)); texture.SetPixel(x,y,new Color(1,1,1,alpha));
            }
            texture.Apply(); File.WriteAllBytes(folder+"/"+name+".png",texture.EncodeToPNG()); UnityEngine.Object.DestroyImmediate(texture);
            AssetDatabase.ImportAsset(folder+"/"+name+".png",ImportAssetOptions.ForceSynchronousImport);
            var material=AssetDatabase.LoadAssetAtPath<Material>(folder+"/"+name+".mat");
            if(!material) { material=new Material(Shader.Find("Universal Render Pipeline/Particles/Unlit")); AssetDatabase.CreateAsset(material,folder+"/"+name+".mat"); }
            material.SetTexture("_BaseMap",AssetDatabase.LoadAssetAtPath<Texture2D>(folder+"/"+name+".png"));
            material.SetFloat("_Surface",1); material.SetFloat("_ZWrite",0); material.SetFloat("_SrcBlend",5); material.SetFloat("_DstBlend",10);
            material.EnableKeyword("_SURFACE_TYPE_TRANSPARENT"); material.renderQueue=3000; EditorUtility.SetDirty(material);
        }
    }
}
