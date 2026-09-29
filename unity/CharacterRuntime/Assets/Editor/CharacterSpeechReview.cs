using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEngine;
using UnityEditor.SceneManagement;

// Replays the native AVAudioEngine fixture's real frame trace into the existing
// authored-mouth driver. It changes only temporary scene instances, never assets.
public static class CharacterSpeechReview
{
    [Serializable] sealed class Trace { public Frame[] frames; }
    [Serializable] sealed class Frame { public string kind,state; public float time,level; public int round; }
    [Serializable] sealed class Row {
        public string id,amplitudeShape;
        public int audioFrames,rejected,visemes;
        public float peakMouth,peakVertexDelta,restMouth,headRotationDelta;
    }
    [Serializable] sealed class Report { public string status="PASS"; public int assertions; public List<Row> roles=new List<Row>(); }
    const string Scene="Assets/Scenes/ViewerScene.unity";
    public static void Run()
    {
        var report=new Report();
        void Check(bool ok,string message) { report.assertions++;if(!ok)throw new Exception("CHARACTER_SPEECH_REVIEW: "+message); }
        string output=Path.Combine(CharacterPackageBuilder.Root,".local/checks/lipsync-v052");
        var trace=JsonUtility.FromJson<Trace>(File.ReadAllText(Path.Combine(output,"playback-after.json")));
        Check(trace.frames!=null && trace.frames.Length>20,"actual native audio trace exists");
        EditorSceneManager.OpenScene(Scene);
        try {
            var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
            var camera=UnityEngine.Object.FindFirstObjectByType<Camera>();
            foreach(string id in new[]{"anime-kipfel","anime-mamehinata"}) {
                var source=viewer.characters.Single(x=>x.modelId==id);
                var instance=UnityEngine.Object.Instantiate(source.gameObject);instance.SetActive(true);
                var host=new GameObject("SpeechReview");
                var closed=new Mesh();var opened=new Mesh();
                try {
                    var character=instance.GetComponent<ViewerCharacter>();character.ApplyContract();
                    var driver=host.AddComponent<CompanionAvatarDriver>();driver.Bind(character.transform,camera);driver.SetEnabled(true);
                    Check(!character.Manifest.speech.proceduralHeadMotion,id+" uses only authored mouth shapes");
                    var binding=character.Manifest.speech.amplitude.Single();
                    var skin=CharacterContract.Resolve(character.transform,binding.renderer).GetComponent<SkinnedMeshRenderer>();
                    int index=skin.sharedMesh.GetBlendShapeIndex(binding.shape);
                    Check(index>=0 && binding.shape.StartsWith("vrc.v."),id+" original speech shape resolves");
                    float scale=CharacterContract.MorphScale(skin,index);
                    var head=CharacterContract.Resolve(character.transform,character.Manifest.rig.head);var before=head.localRotation;
                    for(int i=0;i<60;i++)driver.Step(1f/60,i/60f);
                    skin.BakeMesh(closed);var baseline=closed.vertices;
                    var row=new Row {id=id,amplitudeShape=binding.shape};
                    float clock=0;
                    foreach(var frame in trace.frames) {
                        if(frame.kind=="state")driver.SetState(frame.state);
                        if(frame.kind=="frame") {
                            row.audioFrames++;
                            if(!driver.SetSpeech(frame.time,frame.level,null))row.rejected++;
                        }
                        for(int i=0;i<4;i++){clock+=.01f;driver.Step(.01f,clock);}
                        float weight=skin.GetBlendShapeWeight(index)/scale;
                        if(weight>row.peakMouth) {
                            row.peakMouth=weight;skin.BakeMesh(opened);var vertices=opened.vertices;
                            for(int v=0;v<vertices.Length;v++)row.peakVertexDelta=Mathf.Max(row.peakVertexDelta,Vector3.Distance(vertices[v],baseline[v]));
                        }
                    }
                    Check(row.rejected==0,id+" all streamed/cached/cancel frames accepted");
                    Check(row.peakMouth>.02f && row.peakVertexDelta>.00001f,id+" real audio moves actual mouth vertices");
                    driver.SetState("idle");for(int i=0;i<60;i++)driver.Step(1f/60,clock+i/60f);
                    row.restMouth=skin.GetBlendShapeWeight(index)/scale;
                    Check(row.restMouth<.0001f,id+" stop returns to closed mouth");
                    foreach(var viseme in character.Manifest.speech.visemes) {
                        driver.SetState("idle");driver.SetSpeech(0,0,new[]{new VisemeValue{id=viseme.id,weight=1}});
                        for(int i=0;i<60;i++)driver.Step(1f/60,i/60f);
                        foreach(var v in viseme.bindings) {
                            var s=CharacterContract.Resolve(character.transform,v.renderer).GetComponent<SkinnedMeshRenderer>();
                            int j=s.sharedMesh.GetBlendShapeIndex(v.shape);
                            Check(j>=0 && Mathf.Abs(s.GetBlendShapeWeight(j)/CharacterContract.MorphScale(s,j)-v.weight)<.001f,id+" authored viseme "+viseme.id);
                        }
                        row.visemes++;
                    }
                    row.headRotationDelta=Quaternion.Angle(before,head.localRotation);
                    Check(row.headRotationDelta<.001f,id+" no additional speech head motion");
                    report.roles.Add(row);
                } finally {
                    UnityEngine.Object.DestroyImmediate(opened);UnityEngine.Object.DestroyImmediate(closed);
                    UnityEngine.Object.DestroyImmediate(host);UnityEngine.Object.DestroyImmediate(instance);
                }
            }
            File.WriteAllText(Path.Combine(output,"unity-mouth-review.json"),JsonUtility.ToJson(report,true));
            Debug.Log("CHARACTER_SPEECH_REVIEW_PASS assertions="+report.assertions);
        } finally { EditorSceneManager.OpenScene(Scene); }
    }
}
