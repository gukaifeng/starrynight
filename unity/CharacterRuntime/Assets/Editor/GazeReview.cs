using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class GazeReview
{
    [Serializable] sealed class Sample { public string model,action,scenario; public float time; public GazeState gaze; }
    [Serializable] sealed class Report { public string status="PASS"; public int checkedFrames; public float frameRateDifference; public List<Sample> samples=new(); }
    static void Require(bool ok,string message) { if(!ok) throw new Exception("GAZE REVIEW: "+message); }
    public static void Run()
    {
        string folder=Path.GetFullPath("../../docs/verification/gaze"); Directory.CreateDirectory(folder);
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var camera=viewer.viewCamera; var report=new Report();
        try
        {
            foreach(var c in viewer.characters)
            {
                foreach(var other in viewer.characters) other.gameObject.SetActive(other==c);
                var player=c.GetComponent<Animation>(); var idle=player.GetClip("Idle");
                idle.SampleAnimation(c.gameObject,0);
                var gaze=viewer.gameObject.AddComponent<CharacterGaze>(); gaze.Bind(c.transform,camera,null);
                if(!c.Manifest.Supports("core.gaze@1"))
                {
                    Require(!gaze.State.available && !gaze.State.independentEyes,c.modelId+" does not opt into host gaze");
                    var original=c.GetComponentsInChildren<Transform>(true).Select(t=>(t,t.localRotation)).ToArray();
                    Require(!gaze.ReactToHeadTouch(),c.modelId+" no host head-touch motion");
                    for(int i=0;i<240;i++) {gaze.Step(1f/120,"");report.checkedFrames++;}
                    gaze.RestorePose();
                    foreach(var (bone,rotation) in original)Require(Quaternion.Angle(bone.localRotation,rotation)<.05f,c.modelId+" opted-out bone unchanged "+bone.name);
                    report.samples.Add(new Sample {model=c.modelId,scenario="source-authored gaze opt-out",gaze=Copy(gaze.State)});
                    UnityEngine.Object.DestroyImmediate(gaze);continue;
                }
                Require(gaze.State.available,c.modelId+" head binding");
                Require(string.IsNullOrEmpty(c.Manifest.rig.leftEye) || gaze.State.independentEyes,c.modelId+" eye binding");
                var h=CharacterContract.Resolve(c.transform,c.Manifest.rig.head);
                Vector3 eyeCenter=h.position+Vector3.up*c.RestBounds().size.y*.035f;
                float radius=c.RestBounds().size.y*.75f;
                camera.aspect=1;
                foreach(var angles in new[]{new Vector2(0,0),new Vector2(-35,5),new Vector2(35,5),new Vector2(65,0),
                    new Vector2(90,0),new Vector2(150,0),new Vector2(-180,0),new Vector2(0,35),new Vector2(0,-35),new Vector2(0,80)})
                {
                    camera.transform.position=eyeCenter+GazeMath.Direction(angles)*radius; camera.transform.LookAt(eyeCenter);
                    for(int i=0;i<240;i++) { gaze.RestorePose(); idle.SampleAnimation(c.gameObject,0); gaze.Step(1f/120,""); Check(gaze.State,c.modelId); report.checkedFrames++; }
                    if(Mathf.Abs(angles.x)<=35 && Mathf.Abs(angles.y)<10 && gaze.State.independentEyes)
                        Require(gaze.State.eyeError<.7f,c.modelId+" forward eye alignment "+gaze.State.eyeError);
                    if(Mathf.Abs(angles.x)>=150 || angles.y>70)
                        Require(Mathf.Abs(gaze.State.headYaw)<.2f && Mathf.Abs(gaze.State.headPitch)<.2f,c.modelId+" unreachable target must release");
                    report.samples.Add(new Sample{model=c.modelId,scenario=angles.ToString(),gaze=Copy(gaze.State)});
                    if(Mathf.Abs(angles.x)==35 || angles.x==150 || angles.y==35 || angles.y==-35 || angles==Vector2.zero)
                        CharacterVisualReview.Render(camera,Path.Combine(folder,c.modelId+"-"+angles.x+"-"+angles.y+".png"),900);
                }
                // Complete animated clips, including a 360-degree turn through the rear hemisphere.
                foreach(string action in c.actions)
                {
                    gaze.RestorePose(); idle.SampleAnimation(c.gameObject,0); gaze.Bind(c.transform,camera,null);
                    camera.transform.position=eyeCenter+new Vector3(radius*.25f,0,radius); camera.transform.LookAt(eyeCenter);
                    var clip=player.GetClip(action); Vector2 previous=Vector2.zero; float maxStep=0;
                    for(int i=0;i<=Mathf.CeilToInt(clip.length*120);i++)
                    {
                        gaze.RestorePose(); clip.SampleAnimation(c.gameObject,i/120f); gaze.Step(1f/120,action);
                        Check(gaze.State,c.modelId+action); report.checkedFrames++;
                        var current=new Vector2(gaze.State.headYaw,gaze.State.headPitch);
                        if(i>0) maxStep=Mathf.Max(maxStep,Vector2.Distance(previous,current)); previous=current;
                        if(i%60==0) report.samples.Add(new Sample{model=c.modelId,action=action,time=i/120f,gaze=Copy(gaze.State)});
                        if(action=="Bow") Require(gaze.State.weight==0,"bow retains intentional downcast gaze");
                    }
                    Require(maxStep<3,c.modelId+action+" discontinuous head step "+maxStep);
                }
                // No animation resampling: unkeyed bones must return without accumulation.
                gaze.RestorePose(); idle.SampleAnimation(c.gameObject,0); gaze.Bind(c.transform,camera,null);
                var rest=c.GetComponentsInChildren<Transform>().Select(t=>(t,t.localRotation)).ToArray();
                for(int i=0;i<2000;i++){ gaze.RestorePose(); gaze.Step(1f/120,""); }
                gaze.RestorePose();
                foreach(var (bone,rotation) in rest) Require(Quaternion.Angle(bone.localRotation,rotation)<.05f,"accumulated bone twist "+bone.name);
                UnityEngine.Object.DestroyImmediate(gaze);
            }
            Vector2 RunRate(int hz)
            {
                Vector2 x=Vector2.zero,v=Vector2.zero;
                for(int i=0;i<hz;i++) GazeMath.Follow(ref x,ref v,new Vector2(35,12),10,1f/hz);
                return x;
            }
            report.frameRateDifference=Vector2.Distance(RunRate(60),RunRate(120));
            Require(report.frameRateDifference<.001f,"60/120 Hz trajectory differs");
            File.WriteAllText(Path.Combine(folder,"engine-review.json"),JsonUtility.ToJson(report,true));
            Debug.Log("GAZE_REVIEW_PASS frames="+report.checkedFrames);
        }
        finally { EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity"); }
    }
    static GazeState Copy(GazeState value)=>JsonUtility.FromJson<GazeState>(JsonUtility.ToJson(value));
    static void Check(GazeState s,string label)
    {
        Require(!float.IsNaN(s.headYaw+s.headPitch+s.eyeError),label+" nonfinite");
        Require(Mathf.Abs(s.headYaw)<=50.01f && s.headPitch<=22.01f && s.headPitch>=-28.01f,label+" head comfort limit");
        Require(Mathf.Abs(s.eyeYaw)<=12.01f && s.eyePitch<=8.01f && s.eyePitch>=-10.01f,label+" eye limit");
        Require(s.weight>=0 && s.weight<=1,label+" weight");
    }
}
