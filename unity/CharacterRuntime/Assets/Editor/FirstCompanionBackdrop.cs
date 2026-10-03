using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// An actual full-frame render, not an avatar card or an invented character image.
// Run through a graphics-capable Editor after changing the default model/composition.
public static class FirstCompanionBackdrop
{
    public static void Build()
    {
        ShaderUtil.allowAsyncCompilation = false;
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer = Object.FindFirstObjectByType<ViewerController>();
        var character = viewer.characters.First(c=>c.modelId=="hatsune-miku");
        foreach(var item in viewer.characters) item.gameObject.SetActive(item==character);
        character.ApplyContract();
        var player = character.GetComponentInChildren<Animation>(true);
        player.GetClip("Idle").SampleAnimation(character.gameObject,0);
        var studio = viewer.GetComponent<CharacterStudioDriver>();
        studio.Bind(character); studio.Configure(new StudioSettings { room="evening" });
        var camera = viewer.viewCamera;
        const int width=1206,height=2622;
        camera.aspect=(float)width/height;
        var rest=character.RestBounds();
        var region=FramingMath.Region(rest,"conversation",false,character.conversationStart);
        var rotation=Quaternion.Euler(FramingMath.Pitch,FramingMath.FrontYaw,0);
        float distance=FramingMath.Distance(region,rotation,camera.aspect,camera.fieldOfView,1,camera.nearClipPlane);
        float lift=Mathf.Lerp(.19f,.015f,Mathf.InverseLerp(.5f,1.4f,camera.aspect));
        var focus=region.center-rotation*Vector3.up*(2*distance*Mathf.Tan(camera.fieldOfView*Mathf.Deg2Rad*.5f)*lift);
        camera.transform.SetPositionAndRotation(focus-rotation*Vector3.forward*distance,rotation);
        var target=new RenderTexture(width,height,24,RenderTextureFormat.ARGB32) { antiAliasing=4 };
        var previous=RenderTexture.active; Texture2D pixels=null;
        try {
            target.Create(); camera.targetTexture=target;
            Shader.WarmupAllShaders();
            RenderPipeline.SubmitRenderRequest(camera,new UniversalRenderPipeline.SingleCameraRequest { destination=target });
            RenderPipeline.SubmitRenderRequest(camera,new UniversalRenderPipeline.SingleCameraRequest { destination=target });
            RenderTexture.active=target;
            pixels=new Texture2D(width,height,TextureFormat.RGB24,false);
            pixels.ReadPixels(new Rect(0,0,width,height),0,0);pixels.Apply();
            var root=Path.GetFullPath(Path.Combine(Application.dataPath,"../../.."));
            var directory=Path.Combine(root,"ios/StarryNight/Resources/Assets.xcassets/FirstCompanionBackdrop.imageset");
            Directory.CreateDirectory(directory);
            File.WriteAllBytes(Path.Combine(directory,"FirstCompanionBackdrop.jpg"),pixels.EncodeToJPG(94));
            File.WriteAllText(Path.Combine(directory,"Contents.json"),"{\"images\":[{\"filename\":\"FirstCompanionBackdrop.jpg\",\"idiom\":\"universal\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}");
            Debug.Log("FIRST_COMPANION_BACKDROP_PASS");
        } finally {
            camera.targetTexture=null;RenderTexture.active=previous;
            if(pixels) Object.DestroyImmediate(pixels);target.Release();Object.DestroyImmediate(target);
            EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        }
    }
}
