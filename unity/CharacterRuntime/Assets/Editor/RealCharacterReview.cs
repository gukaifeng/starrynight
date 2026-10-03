using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using ModelSpace;

public static class RealCharacterReview
{
    public static void Capture()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var character=viewer.characters.Single(c=>c.modelId=="real-woman");
        foreach(var c in viewer.characters)c.gameObject.SetActive(c==character);
        var animation=character.GetComponent<Animation>();animation.GetClip("Idle").SampleAnimation(character.gameObject,0);
        var driver=viewer.GetComponent<CharacterStudioDriver>();driver.Bind(character);driver.Configure(new StudioSettings());
        var camera=viewer.viewCamera;camera.aspect=1;
        string directory=Path.GetFullPath("../../docs/verification/studio");Directory.CreateDirectory(directory);
        var bounds=character.RestBounds();
        camera.transform.position=bounds.center+new Vector3(0,.08f,3.6f);camera.transform.LookAt(bounds.center);
        CharacterVisualReview.Render(camera,Path.Combine(directory,"human-full.png"));
        Portrait(camera,character);
        CharacterVisualReview.Render(camera,Path.Combine(directory,"human-portrait.png"));
        string thumbnail=Path.GetFullPath("../../ios/StarryNight/Resources/Assets.xcassets/HumanThumbnail.imageset");Directory.CreateDirectory(thumbnail);
        File.Copy(Path.Combine(directory,"human-portrait.png"),Path.Combine(thumbnail,"HumanThumbnail.png"),true);
        File.WriteAllText(Path.Combine(thumbnail,"Contents.json"),"{\"images\":[{\"filename\":\"HumanThumbnail.png\",\"idiom\":\"universal\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}");
        driver.Configure(new StudioSettings{hair="bob",room="evening",faceWidth=.8f,jawShape=.7f,eyeSize=.65f,mouthShape=.75f,skin="warm",lightAngle=45,lightHeight=32});
        CharacterVisualReview.Render(camera,Path.Combine(directory,"custom-portrait.png"));
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        Debug.Log("REAL_CHARACTER_REVIEW_READY");
    }
    public static void Portrait(Camera camera,ViewerCharacter character)
    {
        var head=character.GetComponentsInChildren<SkinnedMeshRenderer>().Single(t=>t.name=="Head");
        var target=head.bounds.center+Vector3.up*.015f;
        camera.transform.position=target+new Vector3(.035f,0,1.02f);camera.transform.LookAt(target);camera.aspect=1;
    }
}
