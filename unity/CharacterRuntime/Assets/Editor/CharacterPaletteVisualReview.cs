using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public static class CharacterPaletteVisualReview
{
    [Serializable] class Row {public string role;public float neutralDifference,gradedDifference,restoredDifference;}
    [Serializable] class Report {public string status="PASS",scope="fixed pose actual Editor Metal URP pixels; not device FPS";public List<Row> characters=new List<Row>();}
    public static void Capture()
    {
        CharacterPaletteBuilder.Prepare();
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        // Camera dithering deliberately changes RGB rounding every render;
        // disable it for a deterministic shader-equivalence pixel comparison.
        viewer.viewCamera.GetUniversalAdditionalCameraData().dithering=false;
        foreach(var source in viewer.characters)source.gameObject.SetActive(false);
        string directory=Path.GetFullPath(Path.Combine(Application.dataPath,"../../../.local/checks/palette-v098/metal"));Directory.CreateDirectory(directory);
        var report=new Report();
        foreach(string id in new[]{"anime-chiffon","anime-hikarun","anime-mizuki","anime-ramune"})
        {
            var source=viewer.characters.Single(x=>x.modelId==id);
            var instance=UnityEngine.Object.Instantiate(source.gameObject);instance.SetActive(true);
            try
            {
                foreach(var animation in instance.GetComponentsInChildren<Animator>(true)) {animation.Rebind();animation.Update(0);animation.enabled=false;}
                var character=instance.GetComponent<ViewerCharacter>();character.ApplyContract();
                var bounds=character.RestBounds();var camera=viewer.viewCamera;camera.aspect=1;
                float distance=OrbitMath.FitDistance(bounds,1,camera.fieldOfView)*.85f;
                camera.transform.position=bounds.center+Quaternion.Euler(4,155,0)*Vector3.back*distance;camera.transform.LookAt(bounds.center);
                Render(camera,null); // warm source shader/skin cache
                var original=Render(camera,directory+"/"+id+"-original.png");
                var palette=instance.AddComponent<CharacterPaletteRuntime>();palette.SendMessage("Awake");
                var catalog=palette.Snapshot(id);
                foreach(var slot in catalog.components)palette.Edit(new PaletteEdit {component=slot.id,channel="$main",tone=new PaletteTone()});
                palette.Tick(2);Render(camera,null);
                var neutral=Render(camera,directory+"/"+id+"-neutral.png");
                foreach(var slot in catalog.components)palette.Edit(new PaletteEdit {component=slot.id,channel="$main",tone=new PaletteTone {hue=72,saturation=.8f,exposure=.2f,tint=.1f}});
                palette.Tick(2);Render(camera,null);
                var graded=Render(camera,directory+"/"+id+"-graded.png");
                palette.Reset(null,true);Render(camera,null);
                var restored=Render(camera,directory+"/"+id+"-restored.png");
                var row=new Row {role=id,neutralDifference=Difference(original,neutral),gradedDifference=Difference(original,graded),restoredDifference=Difference(original,restored)};
                if(row.neutralDifference>.002f || row.restoredDifference>.002f || row.gradedDifference<.001f)
                    throw new Exception("PALETTE_PIXELS_FAILED "+JsonUtility.ToJson(row));
                report.characters.Add(row);
            }
            finally {UnityEngine.Object.DestroyImmediate(instance);}
        }
        File.WriteAllText(directory+"/report.json",JsonUtility.ToJson(report,true));
        Debug.Log("PALETTE_METAL_PASS roles="+report.characters.Count);
    }
    static float Difference(Color32[] a,Color32[] b)
    {double total=0;for(int i=0;i<a.Length;i++)total+=Math.Abs(a[i].r-b[i].r)+Math.Abs(a[i].g-b[i].g)+Math.Abs(a[i].b-b[i].b);return (float)(total/(a.Length*3*255));}
    static Color32[] Render(Camera camera,string path)
    {
        var skins=UnityEngine.Object.FindObjectsByType<SkinnedMeshRenderer>(FindObjectsSortMode.None).Where(x=>x.enabled).ToArray();
        var snapshots=new List<GameObject>();
        foreach(var skin in skins)
        {
            var mesh=new Mesh();skin.BakeMesh(mesh,true);var item=new GameObject("PaletteReviewSnapshot");
            item.transform.SetPositionAndRotation(skin.transform.position,skin.transform.rotation);item.transform.localScale=skin.transform.lossyScale;
            item.AddComponent<MeshFilter>().sharedMesh=mesh;var renderer=item.AddComponent<MeshRenderer>();renderer.sharedMaterials=skin.sharedMaterials;
            var block=new MaterialPropertyBlock();for(int i=0;i<skin.sharedMaterials.Length;i++) {skin.GetPropertyBlock(block,i);renderer.SetPropertyBlock(block,i);block.Clear();}
            skin.enabled=false;snapshots.Add(item);
        }
        var target=new RenderTexture(640,640,24,RenderTextureFormat.ARGB32) {antiAliasing=4};target.Create();
        var previous=RenderTexture.active;var prior=camera.targetTexture;camera.targetTexture=target;
        RenderPipeline.SubmitRenderRequest(camera,new UniversalRenderPipeline.SingleCameraRequest {destination=target});
        RenderTexture.active=target;var image=new Texture2D(640,640,TextureFormat.RGB24,false);
        image.ReadPixels(new Rect(0,0,640,640),0,0);image.Apply();var pixels=image.GetPixels32();
        if(path!=null)File.WriteAllBytes(path,image.EncodeToPNG());
        RenderTexture.active=previous;camera.targetTexture=prior;UnityEngine.Object.DestroyImmediate(image);target.Release();UnityEngine.Object.DestroyImmediate(target);
        foreach(var item in snapshots) {UnityEngine.Object.DestroyImmediate(item.GetComponent<MeshFilter>().sharedMesh);UnityEngine.Object.DestroyImmediate(item);}
        foreach(var skin in skins)skin.enabled=true;
        return pixels;
    }
    public static void FinalSimulator() {CharacterPaletteReview.Run();Capture();CharacterPaletteBuilder.ExportSimulator();}
}
