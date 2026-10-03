using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class EmotionStandardReview {
    [Serializable] sealed class Row {public string actor;public int combinations,joints,fingers,faces;public float maximumFrame,footError,addedPenetration;public EmotionMapping[] mappings;}
    [Serializable] sealed class Report {public string scope="16 original rigs; 126 variants; 60 Hz numerical motion/contact sampling, not device frame rate.";public int assertions;public List<Row> rows=new List<Row>();}
    static Report report;
    static void Check(bool ok,string message){report.assertions++;if(!ok)throw new Exception("EMOTION_STANDARD_REVIEW: "+message);}
    static bool composedOnly;
    public static void Composed(){composedOnly=true;Run();}
    public static void Run() {
        report=new Report();var catalog=EmotionPerformanceStandard.Catalog;
        Check(catalog.entries.Length==42,"all semantic controls");
        foreach(var entry in catalog.entries) {
            Check(entry.variants.Length==3 && entry.variants.Select(v=>v.@base).Distinct().Count()==3,entry.id+" three different choreographies");
            string last="";
            for(int i=0;i<50;i++){string id=EmotionPerformanceStandard.Choose(entry.kind,entry.id,last);var next=EmotionPerformanceStandard.Variant(id);Check(next.@base!=last,"never consecutive same body composition");last=next.@base;}
        }
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        Check(viewer.characters.Length==16,"active roster");foreach(var source in viewer.characters)source.gameObject.SetActive(false);
        var host=new GameObject("EmotionStandardReview");var emotion=host.AddComponent<HostEmotionMotion>();var natural=host.AddComponent<AvatarNaturalMotion>();
        try {
            foreach(var source in viewer.characters.Where(c=>string.IsNullOrEmpty(Environment.GetEnvironmentVariable("STARRY_EMOTION_REVIEW_ACTORS")) || Environment.GetEnvironmentVariable("STARRY_EMOTION_REVIEW_ACTORS").Split(',').Contains(c.modelId))) {
                var c=UnityEngine.Object.Instantiate(source);c.gameObject.SetActive(true);c.ApplyContract();
                try {
                    foreach(var component in c.GetComponentsInChildren<MonoBehaviour>(true))component.enabled=false;
                    var animation=c.GetComponent<Animation>();animation.GetClip("Idle").SampleAnimation(c.gameObject,0);animation.enabled=false;
                    var author=c.GetComponent<AvatarControlDriver>();if(author){author.Reset();author.animator.Update(.02f);author.animator.enabled=false;}
                    var rig=c.GetComponent<HostEmotionRig>();emotion.Bind(c,null);emotion.Configure(true);natural.Bind(c,null,null,emotion);
                    var clothing=c.GetComponent<AvatarClothingClearance>();var row=new Row {actor=c.modelId,joints=natural.State.joints,fingers=natural.State.fingers,faces=rig.faces.Length,mappings=EmotionPerformanceStandard.Map(c,rig)};report.rows.Add(row);
                    Check(emotion.State.supported && natural.State.supported,c.modelId+" supported");Check(row.mappings.Length==42,c.modelId+" all controls mapped");
                    string priorStyle="";
                    for(int i=0;i<6;i++) {
                        Check(emotion.Standard("emotion",i%2==0?"happy":"playful","whisper",false,3)==null,"composed style accepted");
                        Check(emotion.State.standardStyleVariant.Length>0 && emotion.State.standardStyleVariant!=priorStyle,"no consecutive composed style variation");
                        priorStyle=emotion.State.standardStyleVariant;
                        for(int frame=0;frame<250;frame++)emotion.Step(1f/60);
                    }

                    var bones=rig.joints.Concat(rig.naturalJoints).Select(j=>j.bone).Distinct().ToArray();
                    var rp=c.transform.position;var rr=c.transform.rotation;var rs=c.transform.localScale;
                    foreach(var variant in (composedOnly?catalog.entries.Where(e=>e.kind=="emotion").Select(e=>e.variants[0]):catalog.entries.SelectMany(e=>e.variants))) {
                        clothing.Restore();emotion.RestorePose();natural.Restore();emotion.Clear();emotion.Bind(c,null);emotion.Configure(true);
                        if(composedOnly) {emotion.SetSpeech(true);Check(emotion.Standard("emotion",variant.id.Split('.')[1],"shouting",false,1.8f)==null,"sentence accepted");Check(emotion.Standard("vocal","laugh")==null,"vocal composed");}
                        else Check(emotion.Request(variant.id,true)==null,c.modelId+" accepts "+variant.id);
                        Quaternion[] previous=null;
                        int frames=Mathf.CeilToInt((composedOnly?2.5f:variant.duration)*60)+3;
                        for(int frame=0;frame<frames;frame++) {
                            clothing.Restore();emotion.RestorePose();natural.Restore();
                            var raw=bones.Select(b=>b.localRotation).ToArray();natural.Step(1f/60);emotion.Step(1f/60);clothing.Step(1f/60);
                            Check(natural.State.footError<.004f,c.modelId+" grounded "+variant.id);row.footError=Mathf.Max(row.footError,natural.State.footError);
                            Check(clothing.State.maximumAddedPenetration<.001f,c.modelId+" clothing budget "+variant.id);row.addedPenetration=Mathf.Max(row.addedPenetration,clothing.State.maximumAddedPenetration);
                            var current=bones.Select((b,i)=>Quaternion.Inverse(raw[i])*b.localRotation).ToArray();
                            for(int i=0;i<current.Length;i++) {Check(float.IsFinite(current[i].x+current[i].y+current[i].z+current[i].w),"finite pose");if(previous!=null) {var delta=CharacterAutonomy.MotionAngle(previous[i],current[i]);if(delta>5)Debug.Log("EMOTION_STANDARD_FRAME "+c.modelId+" "+variant.id+" bone="+bones[i].name+" frame="+frame+" delta="+delta);row.maximumFrame=Mathf.Max(row.maximumFrame,delta);}}
                            previous=current;Check(c.transform.position==rp && c.transform.rotation==rr && c.transform.localScale==rs,"root untouched");
                        }
                        Check(row.maximumFrame<6,c.modelId+" bounded continuous motion "+row.maximumFrame);row.combinations++;
                    }
                    Debug.Log("EMOTION_STANDARD_ROLE_PASS "+row.actor+" variants="+row.combinations+" maxFrame="+row.maximumFrame);
                } finally {emotion.Clear();natural.Clear();UnityEngine.Object.DestroyImmediate(c.gameObject);}
            }
        } finally {UnityEngine.Object.DestroyImmediate(host);}
        var output=Path.Combine(CharacterPackageBuilder.Root,".local/checks/emotion-standard");Directory.CreateDirectory(output);
        File.WriteAllText(Path.Combine(output,(composedOnly?"composed-review.json":"review.json")),JsonUtility.ToJson(report,true));Debug.Log("EMOTION_STANDARD_PASS assertions="+report.assertions);
    }
}
