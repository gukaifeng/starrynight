using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// Actual engine renders for art/animation review; these never substitute for device FPS evidence.
public static class CharacterVisualReview
{
    public static void Capture()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=Object.FindFirstObjectByType<ViewerController>();var character=viewer.characters.Single(c=>c.modelId=="hatsune-miku");
        foreach(var c in viewer.characters)c.gameObject.SetActive(c==character);
        var camera=viewer.viewCamera;camera.aspect=1;var bounds=character.RestBounds();
        float distance=OrbitMath.FitDistance(bounds,1,camera.fieldOfView)*.86f;
        var animation=character.GetComponent<Animation>();
        string folder=Path.GetFullPath("../../.local/checks/miku-art-review");Directory.CreateDirectory(folder);
        foreach(string action in new[]{"Idle","Wave","Jump","Dance","Bow","Spin","Greet","Cheer","No"})
        {
            var clip=animation.GetClip(action);clip.SampleAnimation(character.gameObject,action=="Idle"?0:clip.length*.45f);
            camera.transform.position=bounds.center+Quaternion.Euler(12,OrbitMath.DefaultYaw,0)*Vector3.back*distance;camera.transform.LookAt(bounds.center);
            Render(camera,Path.Combine(folder,action+".png"));
        }
        animation.GetClip("Idle").SampleAnimation(character.gameObject,0);
        var head=character.GetComponentsInChildren<Transform>().Single(t=>t.name=="頭");
        var target=head.position+new Vector3(0,.26f,0);
        camera.transform.position=target+Quaternion.Euler(5,170,0)*Vector3.back*2.65f;camera.transform.LookAt(target);
        Render(camera,Path.Combine(folder,"Face.png"));
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
    }
    public static void Render(Camera camera,string path,int size=1200)
    {
        // Bake current deformed vertices for each still: Editor skinning otherwise reuses
        // the first pose when several render requests occur inside one editor frame.
        var originals=Object.FindObjectsByType<SkinnedMeshRenderer>(FindObjectsSortMode.None);
        var snapshots=new System.Collections.Generic.List<GameObject>();
        foreach(var skin in originals)
        {
            var mesh=new Mesh();skin.BakeMesh(mesh,true);var g=new GameObject("ReviewSnapshot");
            g.transform.SetPositionAndRotation(skin.transform.position,skin.transform.rotation);g.transform.localScale=skin.transform.lossyScale;
            g.AddComponent<MeshFilter>().sharedMesh=mesh;
            var renderer=g.AddComponent<MeshRenderer>();renderer.sharedMaterials=skin.sharedMaterials;
            var properties=new MaterialPropertyBlock();
            for(int slot=0;slot<skin.sharedMaterials.Length;slot++){skin.GetPropertyBlock(properties,slot);renderer.SetPropertyBlock(properties,slot);properties.Clear();}
            skin.enabled=false;snapshots.Add(g);
        }
        var rt=new RenderTexture(size,size,24,RenderTextureFormat.ARGB32){antiAliasing=4};rt.Create();camera.targetTexture=rt;
        RenderPipeline.SubmitRenderRequest(camera,new UniversalRenderPipeline.SingleCameraRequest{destination=rt});
        var previous=RenderTexture.active;RenderTexture.active=rt;var image=new Texture2D(size,size,TextureFormat.RGB24,false);
        image.ReadPixels(new Rect(0,0,size,size),0,0);image.Apply();File.WriteAllBytes(path,image.EncodeToPNG());
        RenderTexture.active=previous;camera.targetTexture=null;Object.DestroyImmediate(image);rt.Release();Object.DestroyImmediate(rt);
        foreach(var g in snapshots){Object.DestroyImmediate(g.GetComponent<MeshFilter>().sharedMesh);Object.DestroyImmediate(g);}
        foreach(var skin in originals)skin.enabled=true;
    }
}
