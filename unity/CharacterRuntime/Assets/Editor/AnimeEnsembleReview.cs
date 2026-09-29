using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class AnimeEnsembleReview
{
    public static void Prepare()
    {
        BuildIos.Setup();BuildIos.Validate();BuildIos.Thumbnail();CharacterPortraitBuilder.Export();Capture();
    }
    public static void Capture() { Capture(false); }
    public static void CaptureAngles() { Capture(true); }
    private static void Capture(bool anglesOnly)
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        string folder=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/anime-ensemble/renders");Directory.CreateDirectory(folder);
        var camera=viewer.viewCamera;camera.aspect=1;
        foreach(var character in viewer.characters.Where(c=>c.modelId.StartsWith("anime-",StringComparison.Ordinal)))
        {
            foreach(var other in viewer.characters)other.gameObject.SetActive(other==character);
            var player=character.GetComponent<Animation>();var bounds=character.RestBounds();
            float distance=OrbitMath.FitDistance(bounds,1,camera.fieldOfView)*1.08f;
            if(!anglesOnly) foreach(string action in character.Manifest.actions.Select(a=>a.id))
            {
                var clip=player.GetClip(action);
                foreach(float phase in new[]{.2f,.5f,.8f})
                {
                    clip.SampleAnimation(character.gameObject,clip.length*phase);
                    camera.transform.position=bounds.center+Quaternion.Euler(5,180,0)*Vector3.back*distance;
                    camera.transform.LookAt(bounds.center);
                    CharacterVisualReview.Render(camera,Path.Combine(folder,character.modelId+"-"+action+"-"+(int)(phase*100)+".png"),600);
                }
            }
            player.GetClip("Idle").SampleAnimation(character.gameObject,0);
            // The room's back wall occludes a rear camera. Turn off environment
            // geometry only for these art-review stills, without saving the scene.
            var surroundings=UnityEngine.Object.FindObjectsByType<Renderer>(FindObjectsSortMode.None)
                .Where(r=>r.enabled&&!r.transform.IsChildOf(character.transform)).ToArray();
            foreach(var renderer in surroundings)renderer.enabled=false;
            foreach(float yaw in new[]{90f,270f,0f})
            {
                camera.transform.position=bounds.center+Quaternion.Euler(5,yaw,0)*Vector3.back*distance;camera.transform.LookAt(bounds.center);
                CharacterVisualReview.Render(camera,Path.Combine(folder,character.modelId+"-angle-"+(int)yaw+".png"),600);
            }
            foreach(var renderer in surroundings)renderer.enabled=true;
            Debug.Log("ANIME_REVIEW_PASS "+character.modelId+" clips="+character.Manifest.actions.Length+" springs="+character.GetComponent<AvatarSecondaryMotion>().strands.Length);
        }
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
    }
}
