using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEngine;

// Actual imported skeleton and frozen-render checks, separate from device FPS.
public static class SelectedRosterReview
{
    public static void Prepare()
    {
        BuildIos.PrepareExport();
        ReviewStanding();
    }
    public static void ReviewPrepared()
    {
        BuildIos.Validate();
        CharacterModelAutonomyReview.Validate(UnityEngine.Object.FindFirstObjectByType<ViewerController>());
        BuildIos.Thumbnail();
        ReviewStanding();
    }
    static void ReviewStanding()
    {
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var output=Path.Combine(CharacterPackageBuilder.Root,".local/roster-20261002/standing");
        Directory.CreateDirectory(output);
        foreach(var character in viewer.characters)character.gameObject.SetActive(false);
        foreach(var id in new[]{"anime-mao","anime-mizuki"})
        {
            var character=viewer.characters.Single(c=>c.modelId==id);
            character.gameObject.SetActive(true);
            var idle=character.GetComponentInChildren<Animation>(true).GetClip("Idle");
            var head=character.transform.Find(character.Manifest.rig.head);
            var hips=character.GetComponentsInChildren<Transform>(true).First(t=>t.name=="Hips");
            foreach(var time in new[]{0f,4f})
            {
                idle.SampleAnimation(character.gameObject,time);
                var spine=head.position-hips.position;
                if(spine.y<=0 || new Vector2(spine.x,spine.z).magnitude>spine.y*.5f)
                    throw new Exception("SELECTED_ROSTER_NOT_STANDING: "+id);
                var bounds=character.RestBounds();
                var camera=viewer.viewCamera;camera.aspect=.75f;
                camera.transform.position=bounds.center+Quaternion.Euler(5,OrbitMath.DefaultYaw,0)*Vector3.back*
                    OrbitMath.FitDistance(bounds,.75f,camera.fieldOfView)*1.1f;
                camera.transform.LookAt(bounds.center);
                CharacterPerformanceVisualProbe.RenderFrozenPose(character,camera,Path.Combine(output,id+"-"+time+".png"),720,960);
                Debug.Log("SELECTED_ROSTER_STANDING_PASS "+id+" time="+time+" head="+head.position+" hips="+hips.position);
            }
            character.gameObject.SetActive(false);
        }
        Debug.Log("SELECTED_ROSTER_REVIEW_PASS characters="+viewer.characters.Length);
    }
    public static void ExportDevice()
    {
        CharacterResourceBuilder.PrepareAtmospheres();
        BuildIos.ExportPreparedDevice();
    }
    public static void ExportSimulator()
    {
        CharacterResourceBuilder.PrepareAtmospheres();
        BuildIos.ExportPreparedSimulator();
    }
}
