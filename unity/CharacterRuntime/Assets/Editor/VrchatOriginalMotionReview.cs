using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

// Source fidelity review: the restored Idle must equal the author's standing
// pose plus the author's breath delta, without any host-authored bone motion.
public static class VrchatOriginalMotionReview
{
    const string Scene="Assets/Scenes/ViewerScene.unity";
    [Serializable] sealed class Role
    {
        public string id,standClip,breathClip;
        public int idleSamples,bones,performanceOptions;
        public float maxIdleRotationError,maxIdlePositionError,maxIdleMotion;
        public bool hostHeadTouchDisabled,hostGazeDisabled,hostSpeechMotionDisabled,ambientAirDisabled;
    }
    [Serializable] sealed class Report
    {
        public string status="PASS",scope="actual imported AnimationClip poses compared with source stand and breath; runtime opt-out, touch, semantic cues, speech states, rebind and retained legacy behavior; not a device FPS measurement";
        public int assertions;
        public List<Role> characters=new List<Role>();
        public string legacyCharacter;
    }
    struct Pose {public Vector3 p,s;public Quaternion q;}
    static Report report;
    static void Check(bool ok,string message)
    {if(!ok)throw new Exception("VRCHAT_ORIGINAL_MOTION_REVIEW: "+message);report.assertions++;}
    static Transform[] Bones(GameObject go)=>go.GetComponentsInChildren<Transform>(true).Where(t=>t!=go.transform).ToArray();
    static Pose[] Snapshot(Transform[] bones)=>bones.Select(t=>new Pose {p=t.localPosition,q=t.localRotation,s=t.localScale}).ToArray();
    static void Restore(Transform[] bones,Pose[] values)
    {for(int i=0;i<bones.Length;i++){bones[i].localPosition=values[i].p;bones[i].localRotation=values[i].q;bones[i].localScale=values[i].s;}}
    static void Unchanged(Transform[] bones,Pose[] values,string message)
    {
        for(int i=0;i<bones.Length;i++)Check(Vector3.Distance(bones[i].localPosition,values[i].p)<1e-6f &&
            Quaternion.Angle(bones[i].localRotation,values[i].q)<.06f && Vector3.Distance(bones[i].localScale,values[i].s)<1e-6f,message+"/"+bones[i].name);
    }
    public static void BuildAndReview(){BuildIos.Setup();BuildIos.Validate();Run();CharacterPerformanceReview.Run();}
    public static void ReviewAndExportSimulator(){BuildIos.Validate();Run();CharacterPerformanceReview.Run();BuildIos.ExportPreparedSimulator();}
    public static void Run()
    {
        report=new Report();EditorSceneManager.OpenScene(Scene);
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var host=new GameObject("OriginalMotionReviewDriver");
        var actions=host.AddComponent<CharacterActions>();
        var speech=host.AddComponent<CompanionAvatarDriver>();
        var gaze=host.AddComponent<CharacterGaze>();
        var director=host.AddComponent<CharacterDirector>();
        var instances=new List<GameObject>();
        try
        {
            // A normal character is exercised before and after both opt-outs;
            // neither disabled capability nor an old pose may leak across Bind.
            var legacy=viewer.characters.FirstOrDefault(c=>c.modelId=="studio-robot");
            if(legacy) {
            legacy=Clone(legacy,instances);report.legacyCharacter=legacy.modelId;
            Check(new CharacterSpeech().proceduralHeadMotion,"legacy speech default remains enabled");
            Check(JsonUtility.FromJson<CharacterSpeech>("{\"mode\":\"none\"}").proceduralHeadMotion,"omitted speech policy deserializes to legacy default");
            Check(Mathf.Approximately(new SecondaryMotionData().ambientHairAngle,2.2f),"legacy ambient air default unchanged");
            Check(Mathf.Approximately(JsonUtility.FromJson<SecondaryMotionData>("{\"schemaVersion\":1}").ambientHairAngle,2.2f),"omitted ambient policy deserializes to legacy default");
            Bind(legacy,viewer.viewCamera,actions,speech,gaze,director);
            Check(gaze.State.available && gaze.ReactToHeadTouch(),"legacy robot head reaction remains available before source imports");
            VerifyLegacyMotion(legacy,viewer.viewCamera,speech,gaze);
            gaze.RestorePose();speech.RestorePose();
            }
            foreach(string id in new[]{"anime-kipfel","anime-mamehinata"})
            {
                var c=Clone(viewer.characters.Single(x=>x.modelId==id),instances);var m=c.Manifest;
                var row=new Role {id=id,standClip=id=="anime-kipfel"?"VRC_kipfel_stand_still":"VRC_Mamehinata_stand",
                    breathClip=id=="anime-kipfel"?"VRC_kipfel_breath":"VRC_Mamehinata_breath",performanceOptions=m.performance.options.Length};
                report.characters.Add(row);
                Check(m.actions.Length==1 && m.actions[0].id=="Idle",id+" source Idle is the only automatic action");
                Check(m.behaviors.Length==0 && m.interactions.Length==0 && m.effects.Length==0 && m.expressions.Length==0,id+" no invented interaction or semantic responses");
                Check(!m.Supports("core.gaze@1") && !m.speech.proceduralHeadMotion,id+" source has no host gaze or speech nods");
                Check(row.performanceOptions==(id=="anime-kipfel"?82:48),id+" all original performance options retained");
                Check(c.GetComponent<AvatarSecondaryMotion>().ambientHairAngle==0,id+" no invented ambient wind");row.ambientAirDisabled=true;
                VerifyIdle(c,row);
                Bind(c,viewer.viewCamera,actions,speech,gaze,director);
                var bones=Bones(c.gameObject);var idle=c.GetComponent<Animation>().GetClip("Idle");
                row.hostHeadTouchDisabled=!gaze.ReactToHeadTouch();row.hostGazeDisabled=!gaze.State.available;
                Check(row.hostHeadTouchDisabled && row.hostGazeDisabled && gaze.State.headReactionCount==0,id+" head touch cannot synthesize a shake");
                var touch=director.Local("interaction.head.tap");Check(touch.code=="NO_RULE" && touch.executed==0,id+" touch semantic has no invented rule");
                var point=(Vector2)viewer.viewCamera.WorldToScreenPoint(CharacterContract.Resolve(c.transform,m.rig.head).position);
                Check(!actions.Tap(point),id+" empty authored hotspots do not react");
                foreach(string request in new[]{"Wave","No","Dance","Jump"})
                    Check(director.Local("action.request",request).code=="ACTION_UNAVAILABLE",id+" removed synthetic clip unavailable "+request);
                foreach(string eventName in new[]{"dialogue.greeting","dialogue.reply","idle.tick"})
                    Check(director.Local(eventName).executed==0,id+" no automatic reaction "+eventName);
                Check(director.Local("expression.request","joy").executed==0 && director.State.expressionCues==0,id+" no fallback expression cue counted");
                foreach(string state in new[]{"idle","listening","thinking","speaking"})
                {
                    speech.SetState(state);speech.SetSpeech(0,.7f,Array.Empty<VisemeValue>());
                    for(int frame=0;frame<60;frame++)
                    {
                        gaze.RestorePose();speech.RestorePose();idle.SampleAnimation(c.gameObject,frame/60f);
                        var expected=Snapshot(bones);speech.Step(1f/60,frame/60f+.35f);gaze.Step(1f/60,"");
                        Unchanged(bones,expected,id+" host "+state+" leaves author bones unchanged");
                    }
                }
                row.hostSpeechMotionDisabled=true;
                gaze.RestorePose();speech.RestorePose();idle.SampleAnimation(c.gameObject,.6f);
                var restored=Snapshot(bones);
                if(legacy) {
                Bind(legacy,viewer.viewCamera,actions,speech,gaze,director);
                Unchanged(bones,restored,id+" return to another actor does not leave head offsets");
                Check(gaze.State.available && gaze.ReactToHeadTouch(),"legacy head reaction restored after "+id);
                VerifyLegacyMotion(legacy,viewer.viewCamera,speech,gaze);
                }
                Bind(c,viewer.viewCamera,actions,speech,gaze,director);
                Check(!gaze.State.available && gaze.State.headReactionCount==0 && !gaze.ReactToHeadTouch(),id+" source policy survives re-entry");
            }
            string path=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/vrchat-original-motion/runtime-review.json");
            Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,JsonUtility.ToJson(report,true)+"\n");
            Debug.Log("VRCHAT_ORIGINAL_MOTION_REVIEW_PASS assertions="+report.assertions);
        }
        finally
        {
            gaze.RestorePose();speech.RestorePose();director.ClearPerformance();
            UnityEngine.Object.DestroyImmediate(host);
            foreach(var instance in instances)if(instance)UnityEngine.Object.DestroyImmediate(instance);
            EditorSceneManager.OpenScene(Scene);
        }
    }
    static ViewerCharacter Clone(ViewerCharacter source,List<GameObject> instances)
    {
        var instance=UnityEngine.Object.Instantiate(source.gameObject);instances.Add(instance);instance.SetActive(true);
        var c=instance.GetComponent<ViewerCharacter>();c.ApplyContract();return c;
    }
    static void VerifyLegacyMotion(ViewerCharacter c,Camera camera,CompanionAvatarDriver speech,CharacterGaze gaze)
    {
        var head=CharacterContract.Resolve(c.transform,c.Manifest.rig.head);var idle=c.GetComponentInChildren<Animation>().GetClip("Idle");
        gaze.RestorePose();speech.RestorePose();idle.SampleAnimation(c.gameObject,0);Quaternion before=head.localRotation;
        Vector3 cameraPosition=camera.transform.position;camera.transform.position=head.position+new Vector3(.5f,.05f,2);
        for(int frame=0;frame<90;frame++){gaze.RestorePose();idle.SampleAnimation(c.gameObject,0);gaze.Step(1f/60,"");}
        Check(Quaternion.Angle(before,head.localRotation)>1,"legacy gaze still turns actual head bone");
        gaze.RestorePose();idle.SampleAnimation(c.gameObject,0);before=head.localRotation;
        speech.SetState("speaking");speech.Step(1f/60,.5f);
        Check(Quaternion.Angle(before,head.localRotation)>.5f,"legacy speech head accent still animates");
        speech.RestorePose();Check(Quaternion.Angle(before,head.localRotation)<.06f,"legacy speech accent restores authored pose");
        camera.transform.position=cameraPosition;
    }
    static void Bind(ViewerCharacter c,Camera camera,CharacterActions actions,CompanionAvatarDriver speech,CharacterGaze gaze,CharacterDirector director)
    {
        director.ClearPerformance();gaze.RestorePose();speech.RestorePose();
        actions.Initialize(c.transform,camera,null);speech.Bind(c.transform,camera);speech.SetEnabled(true);gaze.Bind(c.transform,camera,actions);
        director.Bind(c,actions,speech,gaze);
        actions.OnInteraction=id=> {var region=Array.Find(c.Manifest.interactions,r=>r.id==id);return region!=null && director.Local(region.eventName).executed>0;};
    }
    static void VerifyIdle(ViewerCharacter c,Role row)
    {
        string path="Assets/CharacterPackages/Imported/"+c.modelId+"/"+c.Manifest.source.model;
        var clips=AssetDatabase.LoadAllAssetsAtPath(path).OfType<AnimationClip>().ToArray();
        var stand=clips.Single(x=>x.name==row.standClip);var breath=clips.Single(x=>x.name==row.breathClip);var idle=clips.Single(x=>x.name=="Idle");
        Check(Mathf.Abs(idle.length-breath.length)<.0001f,row.id+" source breath timing preserved");
        Check(!clips.Any(x=>new[]{"Wave","No","Dance","Jump","Bow","Yes","Clap","Think"}.Contains(x.name)),row.id+" no retained synthetic base clips");
        var asset=AssetDatabase.LoadAssetAtPath<GameObject>(path);var source=UnityEngine.Object.Instantiate(asset);source.SetActive(false);
        try
        {
            var bones=Bones(source);row.bones=bones.Length;var rest=Snapshot(bones);
            stand.SampleAnimation(source,0);var standing=Snapshot(bones);
            Restore(bones,rest);breath.SampleAnimation(source,0);var firstBreath=Snapshot(bones);
            var actualBones=bones.Select(b=>c.transform.Find(AnimationUtility.CalculateTransformPath(b,source.transform))).ToArray();
            Check(actualBones.All(b=>b),row.id+" source and packaged bone paths match");
            for(int frame=0;frame<=150;frame++)
            {
                float time=frame*breath.length/150f;Restore(bones,rest);breath.SampleAnimation(source,time);var sample=Snapshot(bones);
                idle.SampleAnimation(c.gameObject,time);
                for(int i=0;i<bones.Length;i++)
                {
                    Quaternion expected=standing[i].q*Quaternion.Inverse(firstBreath[i].q)*sample[i].q;
                    Vector3 position=standing[i].p+sample[i].p-firstBreath[i].p;
                    float rotationError=Quaternion.Angle(expected,actualBones[i].localRotation),positionError=Vector3.Distance(position,actualBones[i].localPosition);
                    row.maxIdleRotationError=Mathf.Max(row.maxIdleRotationError,rotationError);row.maxIdlePositionError=Mathf.Max(row.maxIdlePositionError,positionError);
                    row.maxIdleMotion=Mathf.Max(row.maxIdleMotion,Quaternion.Angle(standing[i].q,actualBones[i].localRotation));
                    Check(rotationError<.1f && positionError<.00005f,row.id+" Idle equals source stand + breath at "+time+"/"+bones[i].name+" (degrees="+rotationError+", metres="+positionError+")");
                }
                row.idleSamples++;
            }
            Check(row.maxIdleMotion>.01f,row.id+" real source breathing preserved, not frozen");
            idle.SampleAnimation(c.gameObject,0);
        }
        finally {UnityEngine.Object.DestroyImmediate(source);}
    }
}
