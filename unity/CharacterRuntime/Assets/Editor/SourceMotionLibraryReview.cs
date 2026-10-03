using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;

public static class SourceMotionLibraryReview
{
    [Serializable] sealed class Row {public string actor,id,label;public int bindings;public bool changed,restored;}
    [Serializable] sealed class Report {public int actors,assertions;public List<Row> motions=new List<Row>();public string scope="All independent source projections, sampling/restoration; not a claim of equivalent VRChat platform behavior or device FPS.";}
    static Report report;
    static void Check(bool ok,string label){if(!ok)throw new Exception("SOURCE_MOTION_REVIEW: "+label);report.assertions++;}
    public static void CompileProbe(){Debug.Log("SOURCE_MOTION_COMPILE_PASS gestures="+HostEmotionMotion.Gestures.Length);}
    public static void BuildAndReview(){BuildIos.Setup();BuildIos.Validate();Run();HostEmotionMotionReview.Run();}
    public static void ReviewPrepared(){BuildIos.Validate();Run();HostEmotionMotionReview.Run();}
    public static void RebuildRigsAndReview()
    {
        // Only host calibration changed: keep the verified source clip assets,
        // materials and original Animator intact instead of reimporting GLBs.
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var c in viewer.characters){
            PrefabUtility.UnpackPrefabInstance(c.gameObject,PrefabUnpackMode.Completely,InteractionMode.AutomatedAction);
            var old=c.GetComponent<HostEmotionRig>();if(old)UnityEngine.Object.DestroyImmediate(old);
            HostEmotionMotionBuilder.Prepare(c,"Assets/CharacterPackages/Imported/"+c.modelId);
            PrefabUtility.SaveAsPrefabAssetAndConnect(c.gameObject,"Assets/Prefabs/Package_"+c.modelId+".prefab",InteractionMode.AutomatedAction);
        }
        CharacterResourceBuilder.Prepare(viewer);
        EditorSceneManager.SaveScene(viewer.gameObject.scene);AssetDatabase.SaveAssets();
        BuildIos.Validate();Run();HostEmotionMotionReview.Run();
    }
    public static void Run()
    {
        report=new Report();EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var source in viewer.characters)source.gameObject.SetActive(false);
        foreach(var source in viewer.characters){
            var c=UnityEngine.Object.Instantiate(source);c.gameObject.SetActive(true);c.ApplyContract();
            var preview=c.GetComponent<SourceMotionPreview>();var author=c.GetComponent<AvatarControlDriver>();
            try{
                Check(preview && preview.entries.Length>0,c.modelId+" library bound");report.actors++;
                Check(c.GetComponent<SourceMotionPreviewRestore>()?.driver==preview,c.modelId+" serialized restore component");
                var rootPos=c.transform.position;var rootRot=c.transform.rotation;var rootScale=c.transform.localScale;
                foreach(var entry in preview.entries){
                    preview.Clear();author.Reset();author.animator.Update(0);
                    var nodes=entry.nodes.Select(n=>(n.target.localPosition,n.target.localRotation,n.target.localScale,n.target.gameObject.activeSelf)).ToArray();
                    var shapes=entry.morphs.Select(m=>m.skin.GetBlendShapeWeight(m.index)).ToArray();
                    var enabled=entry.visible.Select(v=>v.target.enabled).ToArray();
                    Check(AnimationUtility.GetAnimationEvents(entry.clip).Length==0 && AnimationUtility.GetObjectReferenceCurveBindings(entry.clip).Length==0,"data-only clip");
                    var row=new Row {actor=c.modelId,id=entry.id,label=entry.label,bindings=AnimationUtility.GetCurveBindings(entry.clip).Length};report.motions.Add(row);
                    Check(row.bindings>0,"nonempty "+entry.label);Check(author.Select(entry.id,1)==null,"source selection accepted");
                    // Both early and established poses are actually evaluated.
                    for(int frame=0;frame<50;frame++){
                        preview.RestorePose();author.animator.Update(0);preview.Step(1f/60);
                        for(int i=0;i<entry.nodes.Length;i++){
                            var n=entry.nodes[i];Check(float.IsFinite(n.target.localPosition.sqrMagnitude+n.target.localRotation.x+n.target.localScale.sqrMagnitude),"finite node");
                            row.changed|=Vector3.Distance(n.target.localPosition,nodes[i].Item1)>.00001f || CharacterAutonomy.MotionAngle(n.target.localRotation,nodes[i].Item2)>.01f || n.target.gameObject.activeSelf!=nodes[i].Item4;
                        }
                        for(int i=0;i<entry.morphs.Length;i++){var m=entry.morphs[i];var weight=m.skin.GetBlendShapeWeight(m.index);Check(float.IsFinite(weight),"finite morph");row.changed|=Mathf.Abs(weight-shapes[i])>.01f;}
                        for(int i=0;i<entry.visible.Length;i++)row.changed|=entry.visible[i].target.enabled!=enabled[i];
                        Check(c.transform.position==rootPos && c.transform.rotation==rootRot && c.transform.localScale==rootScale,"host root invariant");
                    }
                    if(entry.duration<=.05f)foreach(var morph in entry.morphs){
                        string path=AnimationUtility.CalculateTransformPath(morph.skin.transform,preview.avatar.transform);
                        var binding=EditorCurveBinding.FloatCurve(path,typeof(SkinnedMeshRenderer),"blendShape."+morph.skin.sharedMesh.GetBlendShapeName(morph.index));
                        var curve=AnimationUtility.GetEditorCurve(entry.clip,binding);
                        Check(curve!=null && Mathf.Abs(morph.skin.GetBlendShapeWeight(morph.index)-curve.Evaluate(entry.duration))<.01f,"short authored pose holds target key");
                    }
                    preview.Clear();
                    row.restored=entry.nodes.Select((n,i)=>Vector3.Distance(n.target.localPosition,nodes[i].Item1)<.00001f && CharacterAutonomy.MotionAngle(n.target.localRotation,nodes[i].Item2)<.01f && Vector3.Distance(n.target.localScale,nodes[i].Item3)<.00001f && n.target.gameObject.activeSelf==nodes[i].Item4).All(x=>x)
                        && entry.morphs.Select((m,i)=>Mathf.Abs(m.skin.GetBlendShapeWeight(m.index)-shapes[i])<.01f).All(x=>x)
                        && entry.visible.Select((v,i)=>v.target.enabled==enabled[i]).All(x=>x);
                    Check(row.restored,c.modelId+" restore "+entry.label);
                }
                // A release ends in the same source/controller baseline.
                var candidate=preview.entries.First(e=>e.nodes.Length>0 || e.morphs.Length>0);
                preview.Select(candidate.id);for(int frame=0;frame<40;frame++)preview.Step(1f/60);
                preview.Cancel();for(int frame=0;frame<40;frame++)preview.Step(1f/60);
                Check(!preview.Active && author.Get(SourceMotionPreview.Parameter)==0,"cancel returns to default");
            }finally{if(preview)preview.Clear();UnityEngine.Object.DestroyImmediate(c.gameObject);}
        }
        Check(report.actors==CharacterPackageBuilder.Roster.characters.Length,"roster coverage");
        string output=Path.Combine(CharacterPackageBuilder.Root,".local/checks/source-motion-library");Directory.CreateDirectory(output);
        File.WriteAllText(output+"/review.json",JsonUtility.ToJson(report,true));
        Debug.Log("SOURCE_MOTION_REVIEW_PASS actors="+report.actors+" motions="+report.motions.Count+" assertions="+report.assertions);
    }
}
