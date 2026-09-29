using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

// Diagnostic only: compare actual mesh deformation with imported morph data and GPU
// output. Direct manual weights below are explicitly labelled probes, never app presets.
public static class CharacterPerformanceVisualProbe
{
    [Serializable] sealed class ShapeInfo {public string name;public int index,frames,changedVertices;public float frameScale,maxDelta;}
    [Serializable] sealed class RendererInfo {public string path,mesh;public int vertices,subMeshes;public string[] materials;public bool enabled,active,updateWhenOffscreen;public ShapeInfo[] shapes;}
    [Serializable] sealed class Weight {public string shape;public float value;}
    [Serializable] sealed class MeshState {public string path;public Weight[] weights;public float maxBakedDelta,meanBakedDelta;public int changedVertices;public Bounds bakedBounds;}
    [Serializable] sealed class ProbeCase {public string id,file,frozenFile;public bool animationEnabled;public string[] selections;public MeshState[] beforeRender,afterRender;}
    [Serializable] sealed class Role {public string id,headBinding;public RendererInfo[] renderers;public List<ProbeCase> cases=new List<ProbeCase>();}
    [Serializable] sealed class Report {public string scope="diagnostic manual morphs versus actual driver; imported frame deltas, CPU BakeMesh, and weights around Camera.Render";public List<Role> characters=new List<Role>();}
    static readonly string[] Watch={"eye_close","eye_joy2","mouth_smile","mouth_ω□2","eyebrow_joy","blink","Blink","まばたき","はぅ","ワ2","下"};
    public static void Run()
    {
        const string scene="Assets/Scenes/ViewerScene.unity";
        string output=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/vrchat-performance/visual-probe");
        Directory.CreateDirectory(output);EditorSceneManager.OpenScene(scene);
        var report=new Report();var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var host=new GameObject("PerformanceVisualProbe");var driver=host.AddComponent<CharacterPerformanceDriver>();
        try
        {
            foreach(var character in viewer.characters.Where(c=>c.modelId=="anime-kipfel" || c.modelId=="anime-mamehinata"))
            {
                foreach(var other in viewer.characters)other.gameObject.SetActive(other==character);
                character.ApplyContract();var studio=viewer.GetComponent<CharacterStudioDriver>();studio.Bind(character);
                studio.Configure(new StudioSettings {room=character.modelId=="anime-kipfel"?"garden":"sunroom"},true);
                var skins=character.GetComponentsInChildren<SkinnedMeshRenderer>(true);
                var player=character.GetComponentInChildren<Animation>(true);player.enabled=true;
                player.Stop();player.GetClip("Idle").SampleAnimation(character.gameObject,0);player.Play("Idle");player["Idle"].time=0;player.Sample();
                var initial=skins.ToDictionary(s=>s,s=>Enumerable.Range(0,s.sharedMesh.blendShapeCount).Select(i=>s.GetBlendShapeWeight(i)).ToArray());
                var baseline=skins.ToDictionary(s=>s,s=>Bake(s));
                var head=CharacterContract.Resolve(character.transform,character.Manifest.rig.head);
                var camera=viewer.viewCamera;camera.aspect=.75f;camera.fieldOfView=32;camera.rect=new Rect(0,0,1,1);
                Vector3 focus=head.position+Vector3.up*.055f;camera.transform.position=focus+new Vector3(.025f,.01f,.98f);camera.transform.LookAt(focus);
                var row=new Role {id=character.modelId,headBinding=character.Manifest.rig.headRenderer,renderers=skins.Select(s=>Info(character,s)).ToArray()};report.characters.Add(row);
                void Restore()
                {
                    driver.Clear();player.enabled=true;player.Stop();player.GetClip("Idle").SampleAnimation(character.gameObject,0);player.Play("Idle");player["Idle"].time=0;player.Sample();
                    foreach(var skin in skins)for(int i=0;i<initial[skin].Length;i++)skin.SetBlendShapeWeight(i,initial[skin][i]);
                }
                void Capture(string id)
                {
                    var item=new ProbeCase {id=id,file=character.modelId+"-"+id+".png",animationEnabled=player.enabled,selections=driver.Selections,
                        beforeRender=skins.Select(s=>State(character,s,baseline[s])).ToArray()};
                    string path=Path.Combine(output,item.file);PortraitRefinementReview.Render(camera,path,900,1200);PortraitRefinementReview.Render(camera,path,900,1200);
                    item.afterRender=skins.Select(s=>State(character,s,baseline[s])).ToArray();
                    item.frozenFile=character.modelId+"-"+id+"-frozen.png";RenderFrozenPose(character,camera,Path.Combine(output,item.frozenFile),900,1200);
                    row.cases.Add(item);
                    File.WriteAllText(Path.Combine(output,"report.json"),JsonUtility.ToJson(report,true)+"\n");
                }
                string eye=character.modelId=="anime-kipfel"?"eye_close":"まばたき";
                string smile=character.modelId=="anime-kipfel"?"kipfel-facial-catsmile":"f-bigsmile";
                var bound=CharacterContract.Resolve(character.transform,character.Manifest.rig.headRenderer).GetComponent<SkinnedMeshRenderer>();
                int eyeIndex=bound.sharedMesh.GetBlendShapeIndex(eye);if(eyeIndex<0)throw new Exception("VISUAL_PROBE_SHAPE_MISSING: "+eye);
                Restore();Capture("default");
                Restore();bound.SetBlendShapeWeight(eyeIndex,1);Capture("manual-bound-eye-literal-1");
                Restore();bound.SetBlendShapeWeight(eyeIndex,CharacterContract.MorphScale(bound,eyeIndex));Capture("manual-bound-eye-frame-scale");
                Restore();foreach(var skin in skins)
                {int index=skin.sharedMesh.GetBlendShapeIndex(eye);if(index>=0)skin.SetBlendShapeWeight(index,CharacterContract.MorphScale(skin,index));}
                Capture("manual-all-renderers-eye-frame-scale");
                Restore();driver.Bind(character);driver.Select(smile,1);
                for(int i=0;i<90;i++) {driver.RestoreMorphs();driver.Step(1f/60);player.Sample();driver.ApplyFrame();}
                Capture("driver-smile");
                player.enabled=false;Capture("driver-smile-animation-disabled");
                Restore();bound.updateWhenOffscreen=true;bound.SetBlendShapeWeight(eyeIndex,CharacterContract.MorphScale(bound,eyeIndex));
                Capture("manual-eye-updateWhenOffscreen");
                Restore();var rest=character.RestBounds();focus=new Vector3(rest.center.x,rest.min.y+rest.size.y*.52f,rest.center.z);
                camera.transform.position=focus+new Vector3(rest.size.y*.16f,rest.size.y*.05f,rest.size.y*1.75f);camera.transform.LookAt(focus);
                Capture("default-fullbody");driver.Bind(character);driver.Select(character.modelId=="anime-kipfel"?"kipfel-sit":"mamehinata-sit",1);
                for(int i=0;i<120;i++)
                {driver.RestoreMorphs();driver.Step(1f/60);foreach(AnimationState state in player)if(state.enabled)state.time+=1f/60;player.Sample();driver.ApplyFrame();}
                Capture("driver-sit");
                driver.Clear();
            }
            File.WriteAllText(Path.Combine(output,"report.json"),JsonUtility.ToJson(report,true)+"\n");
            Debug.Log("CHARACTER_PERFORMANCE_VISUAL_PROBE_DONE characters="+report.characters.Count);
        }
        finally {driver.Clear();UnityEngine.Object.DestroyImmediate(host);EditorSceneManager.OpenScene(scene);}
    }
    // Freeze the already evaluated CPU pose, preserving materials, transforms, shadows,
    // and property blocks. This is an Editor capture adapter for same-frame GPU skinning
    // caches; it never invents a pose or modifies the production model or its mesh assets.
    public static void RenderFrozenPose(ViewerCharacter character,Camera camera,string path,int width,int height)
    {
        var originals=new List<SkinnedMeshRenderer>();var objects=new List<GameObject>();var meshes=new List<Mesh>();
        try
        {
            foreach(var skin in character.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                if(!skin.enabled || !skin.gameObject.activeInHierarchy)continue;
                var mesh=new Mesh {name="EvaluatedPerformancePose"};meshes.Add(mesh);skin.BakeMesh(mesh,false);mesh.RecalculateBounds();
                var baked=new GameObject("EvaluatedPerformancePose") {hideFlags=HideFlags.HideAndDontSave,layer=skin.gameObject.layer};objects.Add(baked);
                baked.transform.SetParent(skin.transform,false);baked.AddComponent<MeshFilter>().sharedMesh=mesh;
                var renderer=baked.AddComponent<MeshRenderer>();renderer.sharedMaterials=skin.sharedMaterials;
                renderer.shadowCastingMode=skin.shadowCastingMode;renderer.receiveShadows=skin.receiveShadows;
                var block=new MaterialPropertyBlock();skin.GetPropertyBlock(block);renderer.SetPropertyBlock(block);block.Clear();
                for(int i=0;i<skin.sharedMaterials.Length;i++) {skin.GetPropertyBlock(block,i);renderer.SetPropertyBlock(block,i);block.Clear();}
                originals.Add(skin);skin.enabled=false;
            }
            PortraitRefinementReview.Render(camera,path,width,height);PortraitRefinementReview.Render(camera,path,width,height);
        }
        finally
        {
            foreach(var original in originals)if(original)original.enabled=true;
            foreach(var item in objects)UnityEngine.Object.DestroyImmediate(item);
            foreach(var mesh in meshes)UnityEngine.Object.DestroyImmediate(mesh);
        }
    }
    static Vector3[] Bake(SkinnedMeshRenderer skin)
    {
        var mesh=new Mesh();try {skin.BakeMesh(mesh,true);return mesh.vertices;}finally {UnityEngine.Object.DestroyImmediate(mesh);}
    }
    static RendererInfo Info(ViewerCharacter character,SkinnedMeshRenderer skin)
    {
        var mesh=skin.sharedMesh;var shapes=new List<ShapeInfo>();var delta=new Vector3[mesh.vertexCount];
        for(int index=0;index<mesh.blendShapeCount;index++)
        {
            string name=mesh.GetBlendShapeName(index);if(!Watch.Contains(name))continue;
            int frames=mesh.GetBlendShapeFrameCount(index);mesh.GetBlendShapeFrameVertices(index,frames-1,delta,null,null);
            shapes.Add(new ShapeInfo {name=name,index=index,frames=frames,frameScale=mesh.GetBlendShapeFrameWeight(index,frames-1),maxDelta=delta.Max(v=>v.magnitude),changedVertices=delta.Count(v=>v.sqrMagnitude>1e-14f)});
        }
        return new RendererInfo {path=AnimationUtility.CalculateTransformPath(skin.transform,character.transform),mesh=mesh.name,vertices=mesh.vertexCount,subMeshes=mesh.subMeshCount,
            materials=skin.sharedMaterials.Select(m=>m?m.name:"<null>").ToArray(),enabled=skin.enabled,active=skin.gameObject.activeInHierarchy,updateWhenOffscreen=skin.updateWhenOffscreen,shapes=shapes.ToArray()};
    }
    static MeshState State(ViewerCharacter character,SkinnedMeshRenderer skin,Vector3[] baseline)
    {
        var current=Bake(skin);float maximum=0;double sum=0;int changed=0;
        for(int i=0;i<current.Length;i++) {float delta=Vector3.Distance(current[i],baseline[i]);maximum=Mathf.Max(maximum,delta);sum+=delta;if(delta>1e-7f)changed++;}
        var bounds=new Bounds(current[0],Vector3.zero);foreach(var point in current)bounds.Encapsulate(point);
        return new MeshState {path=AnimationUtility.CalculateTransformPath(skin.transform,character.transform),maxBakedDelta=maximum,meanBakedDelta=(float)(sum/current.Length),changedVertices=changed,bakedBounds=bounds,
            weights=Enumerable.Range(0,skin.sharedMesh.blendShapeCount).Where(i=>Watch.Contains(skin.sharedMesh.GetBlendShapeName(i))).Select(i=>new Weight {shape=skin.sharedMesh.GetBlendShapeName(i),value=skin.GetBlendShapeWeight(i)}).ToArray()};
    }
}
