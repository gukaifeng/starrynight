using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public static class PortraitRefinementReview
{
    [Serializable] sealed class HeadRow
    {
        public string id;
        public Vector3 scale, bone, renderedCenter, bakedCenter, unscaledCenter;
        public Bounds renderedBounds, bakedBounds;
        public float idleHeadMotion, idleChestMotion;
    }
    [Serializable] sealed class Report { public HeadRow[] heads; }
    public static string Output => Path.Combine(CharacterPackageBuilder.Root,"docs/verification/portrait-refinement");
    public static void Before() { Capture("before"); }
    public static void After() { Capture("after"); }
    public static void Rebuild() { BuildIos.Setup(); BuildIos.Validate(); Capture("after"); }
    public static void ExportPortraits() { BuildIos.Thumbnail(); CharacterPortraitBuilder.Export(); }
    public static void RefineMaterials()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        foreach(var c in UnityEngine.Object.FindFirstObjectByType<ViewerController>().characters)
            if(c.modelId.StartsWith("anime-",StringComparison.Ordinal))
                AnimeCharacterAdapter.PrepareMaterials(c,"Assets/CharacterPackages/Imported/"+c.modelId);
        AssetDatabase.SaveAssets();Capture("after"); ExportPortraits();
    }
    static void Capture(string phase)
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        string directory=Path.Combine(Output,phase);Directory.CreateDirectory(directory);
        var rows=new List<HeadRow>();
        foreach(var c in viewer.characters)
        {
            foreach(var other in viewer.characters)other.gameObject.SetActive(other==c);
            var studio=viewer.GetComponent<CharacterStudioDriver>();studio.Bind(c);studio.Configure(new StudioSettings(),true);
            var player=c.GetComponentInChildren<Animation>();var idle=player.GetClip("Idle");
            idle.SampleAnimation(c.gameObject,0);
            var head=CharacterContract.Resolve(c.transform,c.Manifest.rig.head);
            var renderer=CharacterContract.Resolve(c.transform,c.Manifest.rig.headRenderer).GetComponent<Renderer>();
            var row=new HeadRow {id=c.modelId,scale=renderer.transform.lossyScale,bone=head.position,
                renderedBounds=renderer.bounds,renderedCenter=renderer.bounds.center};
            if(renderer is SkinnedMeshRenderer skin)
            {
                var mesh=new Mesh();skin.BakeMesh(mesh,true);mesh.RecalculateBounds();
                row.bakedBounds=mesh.bounds;row.bakedCenter=skin.transform.TransformPoint(mesh.bounds.center);
                skin.BakeMesh(mesh,false);mesh.RecalculateBounds();row.unscaledCenter=skin.transform.TransformPoint(mesh.bounds.center);
                UnityEngine.Object.DestroyImmediate(mesh);
            }
            Quaternion rest=head.localRotation,chest=head.parent.parent.localRotation;
            for(int i=1;i<=120;i++)
            {
                idle.SampleAnimation(c.gameObject,idle.length*i/120f);
                row.idleHeadMotion=Mathf.Max(row.idleHeadMotion,Quaternion.Angle(rest,head.localRotation));
                row.idleChestMotion=Mathf.Max(row.idleChestMotion,Quaternion.Angle(chest,head.parent.parent.localRotation));
            }
            rows.Add(row);idle.SampleAnimation(c.gameObject,1.5f);
            if(!c.modelId.StartsWith("anime-",StringComparison.Ordinal))continue;
            var bounds=c.RestBounds();var camera=viewer.viewCamera;camera.aspect=.75f;
            var portrait=new Bounds(new Vector3(bounds.center.x,bounds.max.y-bounds.size.y*.27f,bounds.center.z),
                new Vector3(bounds.size.x*.8f,bounds.size.y*.60f,bounds.size.z));
            float distance=OrbitMath.FitDistance(portrait,.75f,camera.fieldOfView)*.94f;
            camera.transform.position=portrait.center+Quaternion.Euler(3,180,0)*Vector3.back*distance;
            camera.transform.LookAt(portrait.center);
            Render(camera,Path.Combine(directory,c.modelId+".png"),900,1200);
        }
        File.WriteAllText(Path.Combine(directory,"geometry.json"),JsonUtility.ToJson(new Report {heads=rows.ToArray()},true));
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        Debug.Log("PORTRAIT_REVIEW_"+phase.ToUpperInvariant()+"_PASS");
    }
    public static void Render(Camera camera,string path,int width,int height)
    {
        bool asynchronous=ShaderUtil.allowAsyncCompilation;
        ShaderUtil.allowAsyncCompilation=false;
        var old=camera.targetTexture;var active=RenderTexture.active;
        var rt=new RenderTexture(width,height,24,RenderTextureFormat.ARGB32);
        var image=new Texture2D(width,height,TextureFormat.RGB24,false);
        try {
            rt.Create();
            camera.targetTexture=rt;
            var request=new UniversalRenderPipeline.SingleCameraRequest {destination=rt};
            // Begin the camera's native rendering context before requesting the
            // readback target in a synchronous Editor batch.
            camera.Render();
            if(!RenderPipeline.SupportsRenderRequest(camera,request))throw new Exception("REVIEW_RENDER_PIPELINE_UNSUPPORTED");
            RenderPipeline.SubmitRenderRequest(camera,request);
            RenderPipeline.SubmitRenderRequest(camera,request);
            RenderTexture.active=rt;image.ReadPixels(new Rect(0,0,width,height),0,0);image.Apply();
            if(!image.GetPixels32().Any(pixel=>pixel.r>8 || pixel.g>8 || pixel.b>8))throw new Exception("REVIEW_RENDER_EMPTY: "+path);
            File.WriteAllBytes(path,image.EncodeToPNG());
        }
        finally { camera.targetTexture=old;RenderTexture.active=active;rt.Release();UnityEngine.Object.DestroyImmediate(rt);UnityEngine.Object.DestroyImmediate(image);ShaderUtil.allowAsyncCompilation=asynchronous; }
    }
}
