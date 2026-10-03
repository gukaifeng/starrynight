using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class AvatarNaturalMotionReview
{
    [Serializable] sealed class Row {public string actor;public int hz,joints,fingers,clothingCapsules,meshCalibrated,armCorrections,clothContacts;public float handTravel,legMotion,footError,maximumFrame,breath,addedPenetration,clothPenetration,physicsMilliseconds;}
    [Serializable] sealed class Report {public string scope="16 saved production avatars; author Animator + shared body layer, numerical 60/120 Hz. Not device FPS.";public int assertions;public List<Row> rows=new List<Row>();}
    static Report report;
    static bool render=true;
    static string Output=>Path.Combine(CharacterPackageBuilder.Root,".local/checks/natural-body-v1");
    static void Check(bool ok,string label){report.assertions++;if(!ok)throw new Exception("NATURAL_BODY_REVIEW: "+label);}
    public static void BuildAndReview(){BuildIos.Setup();BuildIos.Validate();Run();}
    public static void Final(){render=false;Run();Stress();}
    public static void Run()
    {
        report=new Report();Directory.CreateDirectory(Output);
        ReviewSegmentContacts();
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var c in viewer.characters)c.gameObject.SetActive(false);
        var host=new GameObject("NaturalBodyReview");var motion=host.AddComponent<AvatarNaturalMotion>();
        try {
            foreach(var original in viewer.characters) {
                var c=UnityEngine.Object.Instantiate(original);c.gameObject.SetActive(true);c.ApplyContract();
                try {
                    foreach(var component in c.GetComponentsInChildren<MonoBehaviour>(true))component.enabled=false;
                    var author=c.GetComponent<AvatarControlDriver>();var rig=c.GetComponent<HostEmotionRig>();
                    var player=c.GetComponent<Animation>();player.enabled=false;
                    var feet=new[]{rig.leftFoot,rig.rightFoot};var hands=new[]{rig.leftHand,rig.rightHand};
                    var rootPosition=c.transform.position;var rootRotation=c.transform.rotation;var rootScale=c.transform.localScale;
                    var captured=new List<Transform>(rig.joints.Select(j=>j.bone));captured.AddRange(rig.naturalJoints.Select(j=>j.bone));captured=captured.Distinct().ToList();
                    foreach(int hz in new[]{60,120}) {
                        player.GetClip("Idle").SampleAnimation(c.gameObject,0);
                        if(author){author.animator.enabled=true;author.Reset();author.animator.Update(.02f);}
                        motion.Bind(c,null,null,null);Check(motion.State.supported,c.modelId+" supported");Check(motion.State.fingers>=8,c.modelId+" calibrated finger joints");
                        var clothing=c.GetComponent<AvatarClothingClearance>();var secondary=c.GetComponent<AvatarSecondaryMotion>();secondary.ResetSimulation();
                        Check(clothing.State.meshCalibrated>=3,c.modelId+" real garment envelopes calibrated");
                        var firstHands=hands.Select(t=>t.position).ToArray();
                        var row=new Row {actor=c.modelId,hz=hz,joints=motion.State.joints,fingers=motion.State.fingers};report.rows.Add(row);
                        Quaternion[] previousOffset=null;
                        var initialLegs=rig.naturalJoints.Where(j=>j.human.Contains("Leg") || j.human.EndsWith("Foot")).Select(j=>j.bone.localRotation).ToArray();
                        for(int frame=0;frame<hz*20;frame++) {
                            secondary.RestorePose();clothing.Restore();motion.Restore();if(author)author.animator.Update(1f/hz);
                            var raw=captured.Select(t=>t.localRotation).ToArray();var rawPosition=captured.Select(t=>t.localPosition).ToArray();
                            motion.SetSpeech(frame>=hz*10);motion.Step(1f/hz);
                            var timer=System.Diagnostics.Stopwatch.StartNew();clothing.Step(1f/hz);secondary.Step(1f/hz);timer.Stop();
                            row.physicsMilliseconds=Mathf.Max(row.physicsMilliseconds,(float)timer.Elapsed.TotalMilliseconds);
                            Check(clothing.State.maximumAddedPenetration<.001f,c.modelId+" no added sleeve/body intersection "+clothing.State.maximumAddedPenetration);
                            if(hz==60 && (frame==0 || frame==hz*14 ||
                               new[]{"anime-chiffon","anime-hikarun","anime-ichigo","anime-lime"}.Contains(c.modelId) && new[]{hz*4,hz*9}.Contains(frame)))Capture(c,viewer.viewCamera,"body-"+frame);
                            for(int i=0;i<captured.Count;i++) {
                                var q=captured[i].localRotation;Check(float.IsFinite(q.x+q.y+q.z+q.w),c.modelId+" finite");
                                var offset=Quaternion.Inverse(raw[i])*q;
                                if(frame>0)row.maximumFrame=Mathf.Max(row.maximumFrame,CharacterAutonomy.MotionAngle(previousOffset[i],offset));
                                if(previousOffset==null)previousOffset=new Quaternion[captured.Count];previousOffset[i]=offset;
                            }
                            row.footError=Mathf.Max(row.footError,motion.State.footError);
                            foreach(var hand in hands)row.handTravel=Mathf.Max(row.handTravel,Vector3.Distance(firstHands[hand==hands[0]?0:1],hand.position));
                            var legs=rig.naturalJoints.Where(j=>j.human.Contains("Leg") || j.human.EndsWith("Foot")).ToArray();
                            for(int i=0;i<legs.Length;i++)row.legMotion=Mathf.Max(row.legMotion,CharacterAutonomy.MotionAngle(initialLegs[i],legs[i].bone.localRotation));
                            Check(c.transform.position==rootPosition && c.transform.rotation==rootRotation && c.transform.localScale==rootScale,"presentation root untouched");
                            secondary.RestorePose();clothing.Restore();motion.Restore();for(int i=0;i<captured.Count;i++){Check(CharacterAutonomy.MotionAngle(captured[i].localRotation,raw[i])<.001f,"no rotation accumulation");Check(Vector3.Distance(captured[i].localPosition,rawPosition[i])<.00001f,"no translation accumulation");}
                        }
                        Check(row.handTravel>.006f && row.handTravel<.25f,c.modelId+" visible bounded wrist life "+row.handTravel);
                        Check(row.legMotion>.1f && row.legMotion<35,c.modelId+" knee/ankle life "+row.legMotion);
                        Check(row.footError<.004f,c.modelId+" planted feet "+row.footError);
                        Check(row.maximumFrame<3,c.modelId+" smooth per-frame offset "+row.maximumFrame);
                        row.clothingCapsules=clothing.State.capsules;row.meshCalibrated=clothing.State.meshCalibrated;row.armCorrections=clothing.State.armCorrections;
                        row.clothContacts=clothing.State.clothContacts;row.addedPenetration=clothing.State.maximumAddedPenetration;row.clothPenetration=clothing.State.maximumClothPenetration;
                        // Author posture/emote wins; fade all added offsets out.
                        var block=author.profile.parameters.FirstOrDefault(p=>rig.blockingParameters.Contains(p.name));
                        if(block!=null) {
                            author.Set(block.name,block.initial+1);
                            for(int i=0;i<hz*3;i++){motion.Restore();author.animator.Update(1f/hz);motion.Step(1f/hz);}
                            Check(motion.State.suppressed && motion.State.weight<.001f,"author pose owns body");
                            motion.Clear();author.Reset();author.animator.Update(.02f);
                        }
                    }
                    // Existing downloaded v2 rigs work without downloading a new
                    // bundle: verified direct foot chains supply lower-body IK.
                    var calibration=rig.naturalJoints;rig.naturalJoints=Array.Empty<HostEmotionRig.Joint>();
                    motion.Bind(c,null,null,null);Check(motion.State.supported && motion.State.legacyCalibration,"legacy OSS calibration");
                    for(int i=0;i<300;i++){motion.Restore();if(author)author.animator.Update(1f/60);motion.Step(1f/60);}
                    Check(motion.State.footError<.004f,"legacy feet contacts");motion.Clear();rig.naturalJoints=calibration;
                    Debug.Log("NATURAL_BODY_ROLE_PASS "+c.modelId);
                } finally {motion.Clear();UnityEngine.Object.DestroyImmediate(c.gameObject);}
            }
        } finally {UnityEngine.Object.DestroyImmediate(host);}
        File.WriteAllText(Path.Combine(Output,"review.json"),JsonUtility.ToJson(report,true));
        Debug.Log("NATURAL_BODY_REVIEW_PASS rows="+report.rows.Count+" assertions="+report.assertions);
    }
    public static void Stress()
    {
        report=new Report();Directory.CreateDirectory(Output);ReviewSegmentContacts();
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();foreach(var original in viewer.characters)original.gameObject.SetActive(false);
        var host=new GameObject("ClothingStress");var motion=host.AddComponent<AvatarNaturalMotion>();var emotion=host.AddComponent<HostEmotionMotion>();
        try {
            foreach(var original in viewer.characters) {
                var c=UnityEngine.Object.Instantiate(original);c.gameObject.SetActive(true);c.ApplyContract();
                try {
                    foreach(var component in c.GetComponentsInChildren<MonoBehaviour>(true))component.enabled=false;
                    var author=c.GetComponent<AvatarControlDriver>();var rig=c.GetComponent<HostEmotionRig>();
                    c.GetComponent<Animation>().GetClip("Idle").SampleAnimation(c.gameObject,0);author.animator.enabled=true;author.Reset();author.animator.Update(.02f);
                    emotion.Bind(c,null);emotion.Configure(true);motion.Bind(c,null,null,emotion);
                    var clothing=c.GetComponent<AvatarClothingClearance>();var secondary=c.GetComponent<AvatarSecondaryMotion>();secondary.ResetSimulation();
                    var row=new Row {actor=c.modelId,hz=60};report.rows.Add(row);
                    Quaternion[] previous=null;
                    foreach(string gesture in new[]{"welcome","shy","pout","listening"}) {
                        emotion.Request(gesture,true);
                        for(int frame=0;frame<360;frame++) {
                            secondary.RestorePose();clothing.Restore();emotion.RestorePose();motion.Restore();author.animator.Update(1f/60);
                            c.transform.rotation=original.transform.rotation*Quaternion.Euler(3*Mathf.Sin(frame*.027f),25*Mathf.Sin(frame*.019f),0);
                            var raw=rig.joints.Select(j=>j.bone.localRotation).ToArray();
                            motion.SetSpeech(true);motion.Step(1f/60);emotion.Step(1f/60);clothing.Step(1f/60);secondary.Step(1f/60);
                            Check(clothing.State.maximumAddedPenetration<.001f,c.modelId+" expressive arms stay out of outfit "+clothing.State.maximumAddedPenetration);
                            Check(clothing.State.maximumClothPenetration<.001f,c.modelId+" no new accessory/capsule intersection "+clothing.State.maximumClothPenetration);
                            var offset=rig.joints.Select((j,i)=>Quaternion.Inverse(raw[i])*j.bone.localRotation).ToArray();
                            if(previous!=null)for(int i=0;i<offset.Length;i++)row.maximumFrame=Mathf.Max(row.maximumFrame,CharacterAutonomy.MotionAngle(previous[i],offset[i]));
                            previous=offset;
                            if(frame==135)Capture(c,viewer.viewCamera,"collision-"+gesture);
                        }
                        secondary.RestorePose();clothing.Restore();emotion.RestorePose();motion.Restore();
                    }
                    row.meshCalibrated=clothing.State.meshCalibrated;row.clothingCapsules=clothing.State.capsules;row.armCorrections=clothing.State.armCorrections;
                    row.clothContacts=clothing.State.clothContacts;row.addedPenetration=clothing.State.maximumAddedPenetration;row.clothPenetration=clothing.State.maximumClothPenetration;
                    Check(row.maximumFrame<5,c.modelId+" collision release stays continuous "+row.maximumFrame);
                    Debug.Log("CLOTHING_STRESS_ROLE_PASS "+c.modelId);
                } finally {emotion.Clear();motion.Clear();UnityEngine.Object.DestroyImmediate(c.gameObject);}
            }
        } finally {UnityEngine.Object.DestroyImmediate(host);}
        File.WriteAllText(Path.Combine(Output,"clothing-stress.json"),JsonUtility.ToJson(report,true));
        Debug.Log("CLOTHING_STRESS_PASS rows="+report.rows.Count+" assertions="+report.assertions);
    }
    static void ReviewSegmentContacts()
    {
        var tip=new Vector3(1,0,0);var origin=new Vector3(-1,0,0);
        Check(AvatarClothingClearance.ProjectSegment(origin,ref tip,new Vector3(0,-1,0),new Vector3(0,1,0),.1f),"middle collision with both tips outside");
        Check(Mathf.Abs(tip.z)>.1f,"capsule segment deflected out of body");
        var untouched=tip;Check(!AvatarClothingClearance.ProjectSegment(origin,ref tip,Vector3.one*5,Vector3.one*6,.1f) && tip==untouched,"distant collider preserves free motion");
        AvatarClothingClearance.ClosestSegments(Vector3.zero,Vector3.zero,Vector3.one,Vector3.one,out var p,out var q,out _);
        Check(p==Vector3.zero && q==Vector3.one,"degenerate capsules finite");
        AvatarClothingClearance.ClosestSegments(Vector3.zero,Vector3.up,Vector3.right,Vector3.right+Vector3.up,out p,out q,out _);
        Check(Mathf.Abs(Vector3.Distance(p,q)-1)<.00001f,"parallel capsules finite");
    }
    static void Capture(ViewerCharacter c,Camera camera,string gesture)
    {
        if(!render)return;
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
