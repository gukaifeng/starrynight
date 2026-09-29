using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
public static class VrchatImportReview
{
    [Serializable] class Row { public string id; public Bounds rest; public int triangles,bones,morphs,springs; public string[] clips; public float maxHeadDegrees; }
    [Serializable] class Report { public Row[] characters; }
    static string Output=>Path.Combine(CharacterPackageBuilder.Root,"docs/verification/vrchat-import/render");
    public static void BuildAndReview(){BuildIos.Setup();BuildIos.Validate();Capture();BuildIos.Thumbnail();CharacterPortraitBuilder.Export();CharacterCoverBuilder.Export();}
    public static void Capture()
    {
        Directory.CreateDirectory(Output);EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();var rows=new List<Row>();
        foreach(var c in viewer.characters.Where(c=>c.modelId=="anime-kipfel" || c.modelId=="anime-mamehinata"))
        {
            foreach(var actor in viewer.characters)actor.gameObject.SetActive(actor==c);
            c.ApplyContract();var studio=viewer.GetComponent<CharacterStudioDriver>();studio.Bind(c);studio.Configure(new StudioSettings {room=c.modelId=="anime-kipfel"?"garden":"sunroom"},true);
            var anim=c.GetComponentInChildren<Animation>();var idle=anim.GetClip("Idle");idle.SampleAnimation(c.gameObject,0);
            var skins=c.GetComponentsInChildren<SkinnedMeshRenderer>();
            var row=new Row {id=c.modelId,rest=c.RestBounds(),triangles=skins.Sum(s=>s.sharedMesh.triangles.Length/3),bones=skins.SelectMany(s=>s.bones).Distinct().Count(),morphs=skins.Sum(s=>s.sharedMesh.blendShapeCount),springs=c.GetComponent<AvatarSecondaryMotion>().strands.Length,clips=c.Manifest.actions.Select(a=>a.clip).ToArray()};rows.Add(row);
            if(row.rest.size.y<1.2f || row.rest.size.y>2.2f)throw new Exception("VRCHAT_SCALE_INVALID "+c.modelId+" "+row.rest.size);
            var head=CharacterContract.Resolve(c.transform,c.Manifest.rig.head);var rest=head.localRotation;
            foreach(var action in c.Manifest.actions)
            {
                var clip=anim.GetClip(action.clip);if(!clip)throw new Exception("VRCHAT_CLIP_MISSING "+action.id);
                for(int i=0;i<=60;i++)
                {
                    clip.SampleAnimation(c.gameObject,clip.length*i/60f);
                    if(!float.IsFinite(head.position.sqrMagnitude))throw new Exception("VRCHAT_ANIMATION_NONFINITE");
                    row.maxHeadDegrees=Mathf.Max(row.maxHeadDegrees,Quaternion.Angle(rest,head.localRotation));
                }
                clip.SampleAnimation(c.gameObject,action.id=="Idle"?1.5f:clip.length*.5f);
                var b=row.rest;var camera=viewer.viewCamera;camera.aspect=.75f;
                var focus=new Vector3(b.center.x,b.min.y+b.size.y*.62f,b.center.z);
                camera.transform.position=focus+Vector3.forward*b.size.y*1.30f;camera.transform.LookAt(focus);
                // A newly selected shader may complete on the first GPU request.
                // Like production cover capture, warm the same pose once first.
                var output=Path.Combine(Output,c.modelId+"-"+action.id+".png");
                PortraitRefinementReview.Render(camera,output,720,960);
                PortraitRefinementReview.Render(camera,output,720,960);
            }
        }
        File.WriteAllText(Path.Combine(Output,"review.json"),JsonUtility.ToJson(new Report {characters=rows.ToArray()},true)+"\n");
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");Debug.Log("VRCHAT_IMPORT_REVIEW_PASS count="+rows.Count);
    }
}
