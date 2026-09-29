using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using ModelSpace;

public static class RealCharacterBuilder
{
    const string Source = "Assets/ThirdParty/MakeHuman";
    const string Folder = "Assets/RealCharacter";
    [Serializable] sealed class TexturePaths { public string diffuseTexture, normalmapTexture, specularTexture, aomapTexture; }
    [Serializable] sealed class MaterialInfo { public string name; public bool alpha; public TexturePaths textures; }
    [Serializable] sealed class Manifest { public MaterialInfo[] materials; }
    public static GameObject Create()
    {
        if (!File.Exists(Source+"/Xia.fbx")) throw new Exception("Run scripts/prepare_real_character.py before exporting the realistic character");
        Directory.CreateDirectory(Folder); AssetDatabase.Refresh();
        var manifest = JsonUtility.FromJson<Manifest>(File.ReadAllText(Source+"/character-source.json"));
        var importer = (ModelImporter)AssetImporter.GetAtPath(Source+"/Xia.fbx");
        importer.animationType = ModelImporterAnimationType.Legacy; importer.importAnimation = false;
        importer.importBlendShapes = true; importer.isReadable = true; importer.optimizeGameObjects = false;
        importer.meshCompression = ModelImporterMeshCompression.Off;
        importer.importNormals = ModelImporterNormals.Import;
        importer.importBlendShapeNormals = ModelImporterNormals.Calculate;
        importer.normalSmoothingAngle = 180;
        importer.materialImportMode = ModelImporterMaterialImportMode.ImportStandard;
        foreach (var m in manifest.materials)
        {
            var material = CreateMaterial(m);
            importer.AddRemap(new AssetImporter.SourceAssetIdentifier(typeof(Material),m.name),material);
        }
        importer.SaveAndReimport();
        var source = AssetDatabase.LoadAssetAtPath<GameObject>(Source+"/Xia.fbx");
        var root = new GameObject("RealWoman");
        var rig = UnityEngine.Object.Instantiate(source,root.transform); rig.name = "Character";
        foreach (var animator in rig.GetComponentsInChildren<Animator>()) UnityEngine.Object.DestroyImmediate(animator);
        foreach (var player in rig.GetComponentsInChildren<Animation>()) UnityEngine.Object.DestroyImmediate(player);
        var meshes = rig.GetComponentsInChildren<SkinnedMeshRenderer>(true);
        foreach (var renderer in meshes)
        {
            // Blender adds .001 while the authoring object and export copy coexist.
            renderer.name = renderer.name.Split('.')[0];
            renderer.quality = SkinQuality.Bone4; renderer.updateWhenOffscreen = true;
            renderer.sharedMesh = NormalizeShapes(renderer.sharedMesh,renderer.name);
            renderer.localBounds = renderer.sharedMesh.bounds;
            renderer.localBounds = new Bounds(renderer.localBounds.center,renderer.localBounds.size*1.5f);
        }
        var head = rig.GetComponentsInChildren<Transform>().First(t=>t.name=="head"); head.name = "HeadPivot";
        BuildEyePivots(meshes.First(t=>t.name=="Eyes"),head);
        var character = root.AddComponent<ViewerCharacter>(); character.modelId = "real-woman"; character.displayName = "小夏";
        character.conversationStart = .64f;
        character.actions = new[] { "Wave", "Bow", "Greet", "No" };
        var appearance = root.AddComponent<RealCharacterAppearance>(); appearance.meshes = meshes; appearance.stature = root.transform;
        appearance.longHair = meshes.First(t=>t.name=="HairLong").gameObject;
        appearance.bobHair = meshes.First(t=>t.name=="HairBob").gameObject;
        appearance.bobHair.SetActive(false);
        var animation = root.AddComponent<Animation>(); animation.playAutomatically = false;
        foreach (string action in new[] { "Idle", "Wave", "Bow", "Greet", "No" })
        {
            var clip = BuildClip(root,action);
            string path = Folder+"/"+action+".anim";
            var existing = AssetDatabase.LoadAssetAtPath<AnimationClip>(path);
            if (existing) { EditorUtility.CopySerialized(clip,existing); UnityEngine.Object.DestroyImmediate(clip); clip=existing; } else AssetDatabase.CreateAsset(clip,path);
            animation.AddClip(clip,action);
        }
        HumanPostureBuilder.Build(root);
        animation.clip = animation.GetClip("Idle"); animation.GetClip("Idle").SampleAnimation(root,0);
        // Fit the resting, relaxed pose rather than the imported A-pose's wide arms.
        bool first=true; Bounds rest=new Bounds(); var baked=new Mesh();
        foreach (var renderer in meshes.Where(m=>m.gameObject.activeSelf))
        {
            renderer.BakeMesh(baked);
            foreach (var vertex in baked.vertices)
            {
                var point=root.transform.InverseTransformPoint(renderer.transform.TransformPoint(vertex));
                if (first) { rest=new Bounds(point,Vector3.zero); first=false; } else rest.Encapsulate(point);
            }
        }
        UnityEngine.Object.DestroyImmediate(baked);
        character.useAuthoredRestBounds = true; character.authoredRestBounds = rest;
        appearance.Configure(new StudioSettings()); animation.enabled=false;
        return root;
    }
    static Mesh NormalizeShapes(Mesh source,string name)
    {
        var result = UnityEngine.Object.Instantiate(source); result.name = name;
        var dv=new Vector3[source.vertexCount]; var dn=new Vector3[source.vertexCount]; var dt=new Vector3[source.vertexCount];
        result.ClearBlendShapes();
        bool preserveHairNormals=name.StartsWith("Hair");
        if(!preserveHairNormals) result.RecalculateNormals();
        result.RecalculateTangents();
        var basePositions=result.vertices; var baseNormals=result.normals; var baseTangents=result.tangents;
        var targetMesh=UnityEngine.Object.Instantiate(result);
        for (int i=0;i<source.blendShapeCount;i++)
        {
            string key=source.GetBlendShapeName(i); key=key.Substring(key.LastIndexOf('.')+1);
            for (int frame=0;frame<source.GetBlendShapeFrameCount(i);frame++)
            {
                source.GetBlendShapeFrameVertices(i,frame,dv,dn,dt);
                // Rebuild normals from each actual target surface. FBX's sparse normal
                // deltas introduced hard patches around the eyes/lips after morphing.
                targetMesh.vertices=basePositions.Select((p,index)=>p+dv[index]).ToArray();
                targetMesh.RecalculateNormals(); targetMesh.RecalculateTangents();
                var normals=targetMesh.normals; var tangents=targetMesh.tangents;
                for(int vertex=0;vertex<dv.Length;vertex++)
                {
                    dn[vertex]=preserveHairNormals ? Vector3.zero : normals[vertex]-baseNormals[vertex];
                    dt[vertex]=(Vector3)tangents[vertex]-(Vector3)baseTangents[vertex];
                }
                result.AddBlendShapeFrame(key,source.GetBlendShapeFrameWeight(i,frame),dv,dn,dt);
            }
        }
        UnityEngine.Object.DestroyImmediate(targetMesh);
        string path=Folder+"/"+name+".asset";
        var saved=AssetDatabase.LoadAssetAtPath<Mesh>(path);
        if (saved) { EditorUtility.CopySerialized(result,saved); UnityEngine.Object.DestroyImmediate(result); return saved; }
        AssetDatabase.CreateAsset(result,path); return result;
    }
    static Texture2D Texture(string path,bool normal)
    {
        if (string.IsNullOrEmpty(path)) return null;
        path=Source+"/"+path;
        var importer=(TextureImporter)AssetImporter.GetAtPath(path);
        importer.textureType=normal ? TextureImporterType.NormalMap : TextureImporterType.Default;
        importer.sRGBTexture=!normal; importer.mipmapEnabled=true; importer.maxTextureSize=4096;
        importer.textureCompression=TextureImporterCompression.CompressedHQ; importer.anisoLevel=4;
        importer.alphaIsTransparency=!normal;
        var ios=importer.GetPlatformTextureSettings("iPhone"); ios.overridden=true; ios.maxTextureSize=4096;
        ios.format=TextureImporterFormat.ASTC_6x6; ios.compressionQuality=100; importer.SetPlatformTextureSettings(ios);
        importer.SaveAndReimport(); return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }
    static Material CreateMaterial(MaterialInfo m)
    {
        string path=Folder+"/"+m.name+".mat";
        var material=AssetDatabase.LoadAssetAtPath<Material>(path);
        var shader=Shader.Find(m.name=="RealEyes" ? "Xiaoban/Real Eyes" : "Universal Render Pipeline/Lit");
        if (!shader) throw new Exception("Missing realistic material shader");
        if (!material) { material=new Material(shader); AssetDatabase.CreateAsset(material,path); } else material.shader=shader;
        material.SetTexture("_BaseMap",Texture(m.textures.diffuseTexture,false));
        material.SetColor("_BaseColor",Color.white); material.SetFloat("_Metallic",0);
        float smooth=m.name.StartsWith("RealSkin") ? .30f : m.name.StartsWith("RealHair") ? .27f : m.name=="RealEyes" ? .86f : .16f;
        material.SetFloat("_Smoothness",smooth);
        material.SetTexture("_BumpMap",null); material.DisableKeyword("_NORMALMAP");
        if (!string.IsNullOrEmpty(m.textures.normalmapTexture))
        {
            material.SetTexture("_BumpMap",Texture(m.textures.normalmapTexture,true)); material.SetFloat("_BumpScale",m.name.StartsWith("RealClothes") ? .45f : .12f); material.EnableKeyword("_NORMALMAP");
        }
        if (!string.IsNullOrEmpty(m.textures.aomapTexture))
        {
            material.SetTexture("_OcclusionMap",Texture(m.textures.aomapTexture,false)); material.SetFloat("_OcclusionStrength",.4f); material.EnableKeyword("_OCCLUSIONMAP");
        }
        if (m.alpha || m.name=="RealEyes")
        {
            material.SetFloat("_AlphaClip",1); material.SetFloat("_Cutoff",.36f); material.SetFloat("_AlphaToMask",1);
            material.SetFloat("_Cull",0); material.EnableKeyword("_ALPHATEST_ON"); material.renderQueue=2450;
            material.SetOverrideTag("RenderType","TransparentCutout");
        }
        EditorUtility.SetDirty(material); return material;
    }
    static void BuildEyePivots(SkinnedMeshRenderer renderer,Transform head)
    {
        // The source eyes are rigidly weighted to the head. Give each complete eyeball
        // its own pivot; retain topology, materials, UVs and all appearance morphs.
        var mesh=UnityEngine.Object.Instantiate(renderer.sharedMesh); mesh.name="EyesGaze";
        var vertices=mesh.vertices; var centers=new Vector3[2]; var sideBounds=new Bounds[2]; var seen=new bool[2];
        for(int i=0;i<vertices.Length;i++)
        {
            int side=vertices[i].x<0?0:1;
            if(!seen[side]) { sideBounds[side]=new Bounds(vertices[i],Vector3.zero); seen[side]=true; }
            else sideBounds[side].Encapsulate(vertices[i]);
        }
        if(!seen[0] || !seen[1]) throw new Exception("Eyes mesh must contain two separate eyeballs");
        var bones=new Transform[2]; var poses=new Matrix4x4[2];
        for(int side=0;side<2;side++)
        {
            centers[side]=sideBounds[side].center;
            var bone=new GameObject(side==0?"GazeEyeLeft":"GazeEyeRight").transform;
            bone.SetParent(head,false); bone.position=renderer.transform.TransformPoint(centers[side]);
            bone.rotation=Quaternion.identity; bones[side]=bone;
            poses[side]=bone.worldToLocalMatrix*renderer.transform.localToWorldMatrix;
        }
        mesh.boneWeights=vertices.Select(v=>new BoneWeight{boneIndex0=v.x<0?0:1,weight0=1}).ToArray();
        mesh.bindposes=poses;
        string path=Folder+"/EyesGaze.asset";
        var existing=AssetDatabase.LoadAssetAtPath<Mesh>(path);
        if(existing) { EditorUtility.CopySerialized(mesh,existing); UnityEngine.Object.DestroyImmediate(mesh); mesh=existing; }
        else AssetDatabase.CreateAsset(mesh,path);
        renderer.sharedMesh=mesh; renderer.bones=bones;
    }
    static float Ease(float v) { v=Mathf.Clamp01(v); return v*v*v*(v*(v*6-15)+10); }
    static AnimationClip BuildClip(GameObject root,string action)
    {
        var transforms=root.GetComponentsInChildren<Transform>(true);
        var names=transforms.ToDictionary(t=>t.name,t=>t);
        var positions=transforms.Select(t=>t.localPosition).ToArray(); var rotations=transforms.Select(t=>t.localRotation).ToArray();
        var driven=transforms.Where(t=>t.name.StartsWith("spine_") || t.name.StartsWith("upperarm_") || t.name.StartsWith("lowerarm_") || t.name.StartsWith("hand_") || t.name=="HeadPivot" || t.name=="neck_01").ToArray();
        float duration=action=="Idle" ? 5 : action=="No" ? 2.6f : 3.6f;
        int frames=Mathf.CeilToInt(duration*60);
        var curves=driven.ToDictionary(t=>t,t=>Enumerable.Range(0,4).Select(_=>new List<Keyframe>()).ToArray());
        var blink=new List<Keyframe>();
        for (int frame=0;frame<=frames;frame++)
        {
            float time=duration*frame/frames,u=time/duration,p=action=="Idle" ? 0 : Ease(u/.24f)*(1-Ease((u-.74f)/.26f));
            for(int i=0;i<transforms.Length;i++){transforms[i].localPosition=positions[i];transforms[i].localRotation=rotations[i];}
            float breathing=Mathf.Sin(u*Mathf.PI*2);
            names["spine_02"].localRotation*=Quaternion.Euler(.55f*breathing,0,.4f*Mathf.Sin(u*Mathf.PI*2));
            float nod=action=="Bow" ? 8*p : action=="Greet" ? 3*p : .6f*breathing;
            float shake=action=="No" ? 11*Mathf.Sin(u*Mathf.PI*6)*p : 1.1f*breathing;
            names["HeadPivot"].rotation=Quaternion.Euler(nod,shake,.4f*breathing)*names["HeadPivot"].rotation;
            foreach (string side in new[] { "l", "r" })
            {
                var upper=names["upperarm_"+side];var lower=names["lowerarm_"+side];var hand=names["hand_"+side];
                float sign=Mathf.Sign(root.transform.InverseTransformPoint(upper.position).x);
                Vector3 rest=new Vector3(sign*.235f,.70f,.035f);
                Vector3 target=rest;
                if(action=="Wave" && side=="r")target=Vector3.Lerp(rest,new Vector3(sign*(.32f+.018f*Mathf.Sin(time*9)),1.37f,.16f),p);
                if(action=="Greet" && side=="r")target=Vector3.Lerp(rest,new Vector3(sign*.32f,1.20f,.18f),p);
                target.z+=breathing*.004f;
                Solve(upper,lower,hand,root.transform.TransformPoint(target),root.transform.TransformPoint(new Vector3(sign*.75f,1.05f,.25f)));
                if (action=="Wave" && side=="r")hand.localRotation*=Quaternion.Euler(0,0,10*Mathf.Sin(time*9)*p);
            }
            foreach(var bone in driven)
            {
                var q=bone.localRotation;var keys=curves[bone];
                if(frame>0 && Quaternion.Dot(new Quaternion(keys[0][frame-1].value,keys[1][frame-1].value,keys[2][frame-1].value,keys[3][frame-1].value),q)<0)q=new Quaternion(-q.x,-q.y,-q.z,-q.w);
                for(int a=0;a<4;a++)keys[a].Add(new Keyframe(time,q[a]));
            }
            blink.Add(new Keyframe(time,100*(Ease((u-.55f)/.025f)-Ease((u-.582f)/.04f))));
        }
        var clip=new AnimationClip { name=action,legacy=true,frameRate=60,wrapMode=action=="Idle" ? WrapMode.Loop : WrapMode.ClampForever };
        foreach(var bone in driven)for(int axis=0;axis<4;axis++)
            clip.SetCurve(AnimationUtility.CalculateTransformPath(bone,root.transform),typeof(Transform),"localRotation."+"xyzw"[axis],new AnimationCurve(curves[bone][axis].ToArray()));
        foreach(var skin in root.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            if(skin.sharedMesh.GetBlendShapeIndex("Blink")>=0)
                clip.SetCurve(AnimationUtility.CalculateTransformPath(skin.transform,root.transform),typeof(SkinnedMeshRenderer),"blendShape.Blink",new AnimationCurve(blink.ToArray()));
        clip.EnsureQuaternionContinuity();
        for(int i=0;i<transforms.Length;i++){transforms[i].localPosition=positions[i];transforms[i].localRotation=rotations[i];}
        return clip;
    }
    static void Solve(Transform upper,Transform middle,Transform end,Vector3 target,Vector3 pole)
    {
        Vector3 a=upper.position,b=middle.position,c=end.position;
        float l1=Vector3.Distance(a,b),l2=Vector3.Distance(b,c),distance=Mathf.Clamp(Vector3.Distance(target,a),Mathf.Abs(l1-l2)+.001f,l1+l2-.001f);
        Vector3 direction=(target-a).normalized;
        Vector3 bend=Vector3.ProjectOnPlane(pole-a,direction).normalized;
        float along=(l1*l1+distance*distance-l2*l2)/(2*distance),height=Mathf.Sqrt(Mathf.Max(0,l1*l1-along*along));
        Vector3 elbow=a+direction*along+bend*height;
        upper.rotation=Quaternion.FromToRotation(b-a,elbow-a)*upper.rotation;
        middle.rotation=Quaternion.FromToRotation(end.position-middle.position,target-middle.position)*middle.rotation;
    }
}
