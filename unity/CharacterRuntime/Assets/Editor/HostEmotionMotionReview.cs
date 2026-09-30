using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class HostEmotionMotionReview
{
    [Serializable] sealed class Row {public string actor,gesture;public int hz;public float peakDegrees,maxFrameDegrees,maxWristTravel;}
    [Serializable] sealed class Report {public string scope="Host-only upper body; original Animator, masks, cancel/rebind, 60/120 Hz numerical sampling. Not device FPS.";public int assertions;public List<Row> samples=new List<Row>();}
    static Report report;
    static string Output=>Path.Combine(CharacterPackageBuilder.Root,".local/checks/host-emotion-motion");
    static void Check(bool ok,string label){if(!ok)throw new Exception("HOST_EMOTION_REVIEW: "+label);report.assertions++;}
    public static void BuildAndReview(){BuildIos.Setup();BuildIos.Validate();Run();}
    public static void Run()
    {
        report=new Report();Directory.CreateDirectory(Output);
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var c in viewer.characters)c.gameObject.SetActive(false);
        var host=new GameObject("HostEmotionReview");var driver=host.AddComponent<HostEmotionMotion>();
        try {
            foreach(var source in viewer.characters) {
                var c=UnityEngine.Object.Instantiate(source);c.gameObject.SetActive(true);c.ApplyContract();
                try {
                    var author=c.GetComponent<AvatarControlDriver>();
                    var animation=c.GetComponent<Animation>();
                    animation.GetClip("Idle").SampleAnimation(c.gameObject,0);
                    if(author) {author.Reset();author.animator.Update(0);}
                    driver.Bind(c,null);
                    bool pilot=HostEmotionMotionBuilder.Actors.Contains(c.modelId);
                    Check(driver.State.supported==pilot,c.modelId+" explicit opt-in");
                    if(!pilot) {driver.Configure(true);Check(driver.Request("happy",true)=="HOST_MOTION_UNSUPPORTED",c.modelId+" unchanged");continue;}
                    var rig=c.GetComponent<HostEmotionRig>();
                    var feet=c.GetComponentsInChildren<Transform>().Where(t=>t.name=="Foot.L" || t.name=="Foot.R").ToArray();
                    Check(feet.Length==2,c.modelId+" both feet mapped");
                    var hands=c.GetComponentsInChildren<Transform>().Where(t=>t.name=="Hand.L" || t.name=="Hand.R").ToArray();
                    Check(hands.Length==2,c.modelId+" both wrists mapped");
                    var rootPosition=c.transform.position;var rootScale=c.transform.localScale;var rootRotation=c.transform.rotation;
                    foreach(int hz in new[]{60,120})foreach(string gesture in HostEmotionMotion.Gestures) {
                        driver.Clear();driver.Bind(c,null);driver.Configure(true);
                        if(author){author.Reset();author.animator.Update(0);}
                        var feetStart=feet.Select(f=>f.position).ToArray();var handStart=hands.Select(h=>h.position).ToArray();
                        float wristGap=Vector3.Distance(handStart[0],handStart[1]);
                        var previous=rig.joints.Select(j=>j.bone.localRotation).ToArray();
                        var row=new Row {actor=c.modelId,gesture=gesture,hz=hz};report.samples.Add(row);
                        Check(driver.Request(gesture,true)==null,c.modelId+" start "+gesture);
                        for(int frame=0;frame<hz*(HostEmotionMotion.Duration(gesture)+1);frame++) {
                            driver.RestorePose();if(author)author.animator.Update(1f/hz);
                            driver.Step(1f/hz);
                            row.peakDegrees=Mathf.Max(row.peakDegrees,driver.State.peakDegrees);
                            for(int i=0;i<rig.joints.Length;i++) {
                                var q=rig.joints[i].bone.localRotation;
                                Check(float.IsFinite(q.x+q.y+q.z+q.w),"finite quaternion");
                                row.maxFrameDegrees=Mathf.Max(row.maxFrameDegrees,CharacterAutonomy.MotionAngle(previous[i],q));previous[i]=q;
                            }
                            for(int i=0;i<2;i++) {
                                Check(Vector3.Distance(feet[i].position,feetStart[i])<.0001f,c.modelId+" planted feet");
                                row.maxWristTravel=Mathf.Max(row.maxWristTravel,Vector3.Distance(hands[i].position,handStart[i]));
                            }
                            if(hz==60 && (frame==0 || frame==80))Capture(c,viewer.viewCamera,gesture+"-"+frame);
                            if(gesture=="happy" && frame==Mathf.RoundToInt(hz*1.5f))
                                Check(Vector3.Distance(hands[0].position,hands[1].position)>wristGap+.02f,c.modelId+" sleeves open away from body");
                        }
                        Check(row.peakDegrees>4 && row.peakDegrees<28,c.modelId+" useful bounded motion");
                        Check(row.maxFrameDegrees<2.2f,c.modelId+" no frame snaps "+row.maxFrameDegrees);
                        Check(driver.State.gesture=="" && driver.State.completed==1,"natural return");
                        Check(c.transform.position==rootPosition && c.transform.rotation==rootRotation && c.transform.localScale==rootScale,"root invariant");
                    }
                    // Disable during motion: release rather than snap; never reset author controls.
                    driver.Bind(c,null);driver.Configure(true);driver.Request("shy",true);
                    for(int i=0;i<60;i++)driver.Step(1f/60);
                    var weights=author.Values.Select(v=>v.value).ToArray();
                    driver.Configure(false);Check(driver.State.gesture=="shy","disable releases smoothly");
                    for(int i=0;i<60;i++)driver.Step(1f/60);
                    Check(driver.State.weight==0 && driver.State.gesture=="","disable fully unwinds");
                    Check(driver.Request("happy",true)=="HOST_MOTION_DISABLED","off blocks additional motion");
                    Check(weights.SequenceEqual(author.Values.Select(v=>v.value)),"author parameters untouched");
                    // Original gesture remains operable with the extra layer disabled.
                    Check(author.Select("gesture-left-2",1)==null,"original expression still works");
                    driver.Step(.02f);Check(author.Get("GestureLeft")==2,"original gesture preserved");author.Reset();
                    driver.Configure(true);driver.SetInteracting(true);
                    Check(driver.Request("happy",true)=="HOST_MOTION_AUTHOR_PRIORITY","editing has priority");driver.SetInteracting(false);
                    if(c.modelId=="anime-nozomi") {
                        author.Set("StandStyle",1);Check(driver.Request("happy",true)=="HOST_MOTION_AUTHOR_PRIORITY","original body pose wins");author.Reset();
                    }
                    var expression=c.Manifest.performance.options.First(o=>o.ai?.kind=="expression" && o.ai.automatic && HostEmotionMotion.ForIntent(o.ai.intent)!="");
                    Check(driver.CueOriginalExpression(expression.id)==null,"AI source expression maps to host gesture");
                    driver.Step(.03f);driver.Clear();
                    var clean=rig.joints.Select(j=>j.bone.localRotation).ToArray();driver.Step(.03f);
                    Check(clean.SequenceEqual(rig.joints.Select(j=>j.bone.localRotation)),"unbind leaves no actor offsets");
                } finally {driver.Clear();UnityEngine.Object.DestroyImmediate(c.gameObject);}
            }
        } finally {UnityEngine.Object.DestroyImmediate(host);}
        File.WriteAllText(Path.Combine(Output,"review.json"),JsonUtility.ToJson(report,true));
        Debug.Log("HOST_EMOTION_REVIEW_PASS assertions="+report.assertions+" samples="+report.samples.Count);
    }
    static void Capture(ViewerCharacter c,Camera camera,string gesture)
    {
        var bounds=c.RestBounds();var focus=bounds.center;
        camera.aspect=.75f;camera.fieldOfView=34;camera.rect=new Rect(0,0,1,1);
        camera.orthographic=true;camera.orthographicSize=bounds.size.y*.56f;
        camera.cullingMask=1<<30;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=new Color(.08f,.09f,.12f);
        camera.transform.position=focus+new Vector3(0,0,bounds.size.y*3);camera.transform.LookAt(focus);
        foreach(var node in c.GetComponentsInChildren<Transform>(true))node.gameObject.layer=30;
        var skins=c.GetComponentsInChildren<SkinnedMeshRenderer>().Where(s=>s.enabled).ToArray();
        var copies=new List<GameObject>();var meshes=new List<Mesh>();
        try {
            foreach(var skin in skins) {
                var mesh=new Mesh();skin.BakeMesh(mesh);meshes.Add(mesh);
                var go=new GameObject("FrozenReview");go.layer=30;copies.Add(go);go.transform.SetParent(skin.transform,false);
                go.AddComponent<MeshFilter>().sharedMesh=mesh;go.AddComponent<MeshRenderer>().sharedMaterials=skin.sharedMaterials;skin.enabled=false;
            }
            string path=Path.Combine(Output,c.modelId+"-"+gesture+".png");
            PortraitRefinementReview.Render(camera,path,720,960);
            PortraitRefinementReview.Render(camera,path,720,960);
        } finally {foreach(var s in skins)s.enabled=true;foreach(var go in copies)UnityEngine.Object.DestroyImmediate(go);foreach(var m in meshes)UnityEngine.Object.DestroyImmediate(m);}
    }
}
