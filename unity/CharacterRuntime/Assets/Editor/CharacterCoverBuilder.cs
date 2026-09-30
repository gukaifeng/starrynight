using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// Native, authored cover artwork. Does not alter player scenes or export the engine.
public static class CharacterCoverBuilder
{
    [Serializable] sealed class Catalog { public int schemaVersion; public Cover[] covers; }
    [Serializable] sealed class Cover
    {
        public string runtimeID, asset, environmentID,source,sourceSHA256;
        public float focusX, focusY, frameBottom, cameraYaw;
    }
    [Serializable] sealed class Evidence
    {
        public string runtimeID, environmentID, asset,source,sourceSHA256;
        public int width = 1024, height = 768;
        public Vector3 cameraPosition, focus;
    }
    [Serializable] sealed class Report { public int revision = 1; public Evidence[] covers; }
    const string ScenePath = "Assets/Scenes/ViewerScene.unity";
    static string Root => Path.GetFullPath(Path.Combine(Application.dataPath,"../../.."));

    public static void Export()
    {
        var catalog = JsonUtility.FromJson<Catalog>(File.ReadAllText(Path.Combine(Root,"ios/CharacterHost/Resources/CharacterCoverCatalog.json")));
        if(catalog.schemaVersion != 1 || catalog.covers.Select(c=>c.runtimeID).Distinct().Count()!=catalog.covers.Length)
            throw new Exception("CHARACTER_COVER_CATALOG_INVALID");
        EditorSceneManager.OpenScene(ScenePath);
        try
        {
            var viewer = UnityEngine.Object.FindFirstObjectByType<ViewerController>();
            var studio = viewer.GetComponent<CharacterStudioDriver>();
            if(viewer.characters.Length != catalog.covers.Length) throw new Exception("CHARACTER_COVER_SET_INCOMPLETE");
            foreach(var actor in viewer.characters) actor.gameObject.SetActive(false);
            var report = new Report { covers = catalog.covers.Select(cover=>Render(cover,viewer,studio)).ToArray() };
            string folder = Path.Combine(Root,"docs/verification/character-covers"); Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder,"render-report.json"),JsonUtility.ToJson(report,true)+"\n");
            Debug.Log("CHARACTER_COVERS_PASS count="+report.covers.Length);
        }
        finally { EditorSceneManager.OpenScene(ScenePath); }
    }

    static Evidence Render(Cover cover, ViewerController viewer, CharacterStudioDriver studio)
    {
        var source = Array.Find(viewer.characters,c=>c.modelId==cover.runtimeID);
        if(!source || !studio.environment.stages.Any(s=>s.Manifest.id==cover.environmentID))
            throw new Exception("CHARACTER_COVER_SOURCE_MISSING: "+cover.runtimeID);
        if(cover.source=="author-supplied")
        {
            string folder=Path.Combine(Root,"ios/CharacterHost/Assets.xcassets",cover.asset+".imageset");
            string file=Directory.GetFiles(folder,"source.*").Single();byte[] bytes=File.ReadAllBytes(file);
            using(var sha=System.Security.Cryptography.SHA256.Create())
                if(BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant()!=cover.sourceSHA256)throw new Exception("SOURCE_COVER_HASH_MISMATCH");
            var art=new Texture2D(2,2);if(!art.LoadImage(bytes))throw new Exception("SOURCE_COVER_INVALID");
            var evidence=new Evidence {runtimeID=cover.runtimeID,environmentID=cover.environmentID,asset=cover.asset,source=cover.source,sourceSHA256=cover.sourceSHA256,width=art.width,height=art.height};
            UnityEngine.Object.DestroyImmediate(art);return evidence;
        }
        GameObject copy = null, cameraObject = null;
        RenderTexture target = null; Texture2D pixels = null;
        var temporaryMeshes = new List<Mesh>(); var active = RenderTexture.active;
        try
        {
            copy = UnityEngine.Object.Instantiate(source.gameObject);
            copy.name = "AuthoredCoverOnly"; copy.hideFlags = HideFlags.HideAndDontSave;
            foreach(var behaviour in copy.GetComponentsInChildren<Behaviour>(true)) behaviour.enabled = false;
            copy.SetActive(true);
            var model = copy.GetComponent<ViewerCharacter>(); model.ApplyContract();
            var animation = copy.GetComponentInChildren<Animation>(true);
            if(animation && animation.GetClip("Idle")) animation.GetClip("Idle").SampleAnimation(copy,0);
            foreach(var skin in copy.GetComponentsInChildren<SkinnedMeshRenderer>(true))
                for(int i=0;i<skin.sharedMesh.blendShapeCount;i++) skin.SetBlendShapeWeight(i,0);
            foreach(var renderer in copy.GetComponentsInChildren<Renderer>(true))
                for(int i=0;i<renderer.sharedMaterials.Length;i++) renderer.SetPropertyBlock(null,i);
            studio.Bind(model); studio.Configure(new StudioSettings {room=cover.environmentID},true);
            var body = model.RestBounds();
            // Freeze the real model's sampled authored Idle, including skinning and material properties.
            foreach(var skin in copy.GetComponentsInChildren<SkinnedMeshRenderer>())
            {
                if(!skin.enabled) continue;
                var mesh = new Mesh(); temporaryMeshes.Add(mesh); skin.BakeMesh(mesh);
                var baked = new GameObject("CoverMesh"); baked.layer = skin.gameObject.layer;
                baked.transform.SetParent(skin.transform,false);
                baked.AddComponent<MeshFilter>().sharedMesh = mesh;
                var renderer = baked.AddComponent<MeshRenderer>(); renderer.sharedMaterials = skin.sharedMaterials;
                var block = new MaterialPropertyBlock();
                for(int slot=0;slot<skin.sharedMaterials.Length;slot++)
                { skin.GetPropertyBlock(block,slot); renderer.SetPropertyBlock(block,slot); block.Clear(); }
                skin.enabled = false;
            }
            float top = body.max.y + body.size.y*.035f;
            float bottom = body.min.y + body.size.y*cover.frameBottom;
            float halfHeight = (top-bottom)*.5f;
            var focus = new Vector3(body.center.x,(top+bottom)*.5f,body.center.z);
            cameraObject = new GameObject("AuthoredCoverCamera"); cameraObject.hideFlags = HideFlags.HideAndDontSave;
            var camera = cameraObject.AddComponent<Camera>(); camera.enabled = false;
            camera.CopyFrom(viewer.viewCamera); camera.enabled = false;
            camera.aspect = 4f/3; camera.fieldOfView = 30; camera.nearClipPlane = .01f;
            camera.allowHDR = true; camera.allowMSAA = true;
            float distance = halfHeight/Mathf.Tan(camera.fieldOfView*Mathf.Deg2Rad*.5f);
            camera.transform.position = focus + Quaternion.Euler(1,cover.cameraYaw,0)*Vector3.forward*distance;
            camera.transform.LookAt(focus);
            var data = camera.GetUniversalAdditionalCameraData(); data.renderPostProcessing = true;
            data.renderShadows = true; data.dithering = true;
            target = new RenderTexture(1024,768,24,RenderTextureFormat.ARGB32) {antiAliasing=4};
            target.Create(); camera.targetTexture = target;
            var request = new UniversalRenderPipeline.SingleCameraRequest {destination=target};
            if(!RenderPipeline.SupportsRenderRequest(camera,request)) throw new Exception("CHARACTER_COVER_RENDER_UNSUPPORTED");
            // The first request warms all materials. The second captures the same fixed pose.
            RenderPipeline.SubmitRenderRequest(camera,request); RenderPipeline.SubmitRenderRequest(camera,request);
            RenderTexture.active = target;
            pixels = new Texture2D(1024,768,TextureFormat.RGB24,false);
            pixels.ReadPixels(new Rect(0,0,1024,768),0,0); pixels.Apply();
            string folder = Path.Combine(Root,"ios/CharacterHost/Assets.xcassets",cover.asset+".imageset");
            Directory.CreateDirectory(folder); File.WriteAllBytes(Path.Combine(folder,"cover.png"),pixels.EncodeToPNG());
            File.WriteAllText(Path.Combine(folder,"Contents.json"),"{\"images\":[{\"filename\":\"cover.png\",\"idiom\":\"universal\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}\n");
            Debug.Log("CHARACTER_COVER_RENDERED "+cover.runtimeID+" environment="+cover.environmentID);
            return new Evidence {runtimeID=cover.runtimeID,environmentID=cover.environmentID,asset=cover.asset,cameraPosition=camera.transform.position,focus=focus};
        }
        finally
        {
            RenderTexture.active = active;
            if(copy) UnityEngine.Object.DestroyImmediate(copy);
            foreach(var mesh in temporaryMeshes) UnityEngine.Object.DestroyImmediate(mesh);
            if(cameraObject) UnityEngine.Object.DestroyImmediate(cameraObject);
            if(pixels) UnityEngine.Object.DestroyImmediate(pixels);
            if(target) { target.Release(); UnityEngine.Object.DestroyImmediate(target); }
        }
    }
}
