using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor.SceneManagement;
using ModelSpace;

public static class CharacterViewEditorReview
{
    [Serializable] sealed class Report {
        public string status="PASS",scope="Original rigs; temporary +/-18 yaw and +/-8 pitch returns to saved pose; unrestricted editor yaw and bounded +/-80 pitch about fixed body pivot; legacy pitch migration, automatic latest view, reset; neutral portrait bounds on five phone viewports. Rotation never auto-reframes. Not an FPS test.";
        public int revision=CharacterInspectionRotation.Revision,assertions;
        public List<string> viewports=new List<string>();
    }
    static Report report;
    static void Check(bool value,string message) { if(!value)throw new Exception("VIEW_EDITOR_REVIEW: "+message);report.assertions++; }
    static void Tick(CharacterInspectionRotation edit,int frames=180) {
        for(int i=0;i<frames;i++){edit.RestoreFrame();edit.Step(1f/60);edit.ApplyFrame();}
    }
    static bool Near(CharacterViewPose a,CharacterViewPose b) => Mathf.Abs(a.yaw-b.yaw)<.1f && Mathf.Abs(a.pitch-b.pitch)<.1f && Mathf.Abs(a.scale-b.scale)<.002f && Mathf.Abs(a.x-b.x)<.002f && Mathf.Abs(a.y-b.y)<.002f;
    static void ReviewPreview(CharacterInspectionRotation edit,Transform root)
    {
        var before=edit.Current;var target=edit.Target;
        var pivotLocal=root.InverseTransformPoint(edit.DisplayPivot);var pivotWorld=edit.DisplayPivot;
        edit.Preview.Begin();edit.Preview.Move(2,-2);
        for(int frame=0;frame<90;frame++) {
            edit.RestoreFrame();edit.Step(1f/60);edit.ApplyFrame();
            Check(Near(edit.Current,before) && Near(edit.Target,target),"temporary turn cannot change saved pose or draft");
            Check(Vector3.Distance(root.TransformPoint(pivotLocal),pivotWorld)<.00002f,"temporary rotation keeps the body pivot fixed");
            Check(Mathf.Abs(edit.Preview.Offset.x)<=18.001f && Mathf.Abs(edit.Preview.Offset.y)<=8.001f,"small preview envelope");
        }
        Check(edit.Preview.PeakYaw>17 && !edit.Active,"preview is visible without opening editor");
        edit.Preview.End();Tick(edit,120);
        Check(edit.Preview.Offset==Vector2.zero && Near(edit.Current,before),"release returns to the saved custom pose");
        edit.Preview.Begin();edit.Preview.Move(-2,2);Tick(edit,10);
        Check(edit.Begin(),"open editor during preview");
        Check(!edit.Preview.Active,"editor cancels temporary gesture");
        Tick(edit,120);edit.Close();Tick(edit);
        Check(Near(edit.Target,target) && edit.Preview.Offset==Vector2.zero,"opening editor cannot commit a temporary turn");
    }
    public static void ReviewAndExportSimulator() { BuildIos.Validate();Run();BuildIos.ExportPreparedSimulator(); }
    public static void ReviewAndExportDevice() { BuildIos.Validate();Run();BuildIos.ExportPreparedDevice(); }
    public static void Run()
    {
        report=new Report();EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var camera=new GameObject("ViewEditorReviewCamera").AddComponent<Camera>();camera.fieldOfView=35;
        var edit=new CharacterInspectionRotation();GameObject instance=null;
        var hitHost=new GameObject("SavedViewHitReview");var actions=hitHost.AddComponent<CharacterActions>();
        var sizes=new[]{new Vector2(375,667),new Vector2(393,852),new Vector2(402,874),new Vector2(440,956),new Vector2(852,393)};
        try {
            foreach(var source in viewer.characters) {
                instance=UnityEngine.Object.Instantiate(source.gameObject);instance.SetActive(true);
                var character=instance.GetComponent<ViewerCharacter>();character.ApplyContract();
                var bones=instance.GetComponentsInChildren<Transform>(true).Where(t=>t!=instance.transform).ToArray();
                var originals=bones.Select(t=>t.localRotation).ToArray();
                var root=instance.transform;var position=root.position;var rotation=root.rotation;var scale=root.localScale;
                var region=FramingMath.Region(character.RestBounds(),"conversation",false,character.conversationStart);
                edit.Bind(root);actions.Initialize(root,camera,(a,b,c)=>{});
                foreach(var size in sizes) {
                    edit.ResetImmediate();camera.aspect=size.x/size.y;
                    var safe=size.x<size.y ? new Rect(.025f,.08f,.95f,.83f) : new Rect(.09f,.1f,.82f,.85f);
                    var cameraRotation=FramingMath.Rotation(0);
                    float distance=FramingMath.Distance(region,cameraRotation,camera.aspect,camera.fieldOfView,1,camera.nearClipPlane)*CharacterInspectionRotation.TurnFramingReserve;
                    var focus=FramingMath.ImmersiveFocus(region,character.RestBounds(),character.conversationStart,cameraRotation,camera.aspect,camera.fieldOfView,distance);
                    edit.ConstrainComposition(region,cameraRotation,camera.aspect,camera.fieldOfView,safe,ref focus,ref distance);
                    camera.transform.SetPositionAndRotation(focus-cameraRotation*Vector3.forward*distance,cameraRotation);
                    var cameraPosition=camera.transform.position;
                    edit.SetProjection(camera,region,safe);
                    Debug.Log("POSITION_GEOMETRY "+source.modelId+" "+size+" region="+region+" default="+edit.Project(CharacterViewPose.Default)+" turn30="+edit.Project(new CharacterViewPose{yaw=-30,scale=1})+" safe="+safe);
                    Check(edit.Begin(camera.transform.right),"open edit");
                    edit.BeginAdjustment();edit.Move(.075f,0);Tick(edit);
                    Check(edit.Yaw<=-20 && Mathf.Abs(edit.Scale-1)<.00001f && edit.Translation.sqrMagnitude<.000000001f,source.modelId+" "+size+" default turn must work without translating or zooming: "+JsonUtility.ToJson(edit.Current));
                    edit.ResetDraft();Tick(edit);
                    edit.BeginAdjustment(true);edit.TransformView(1.1f,.05f,.04f);Tick(edit);
                    edit.End();var held=edit.Target;Tick(edit);
                    Check(edit.Active && Near(edit.Current,held),"release keeps draft");
                    edit.BeginAdjustment();var before=edit.Current;
                    var pivotLocal=root.InverseTransformPoint(edit.DisplayPivot);var pivotWorld=edit.DisplayPivot;
                    edit.Move(-2.5f,-1.75f);
                    Check(Mathf.Abs(edit.TargetYaw-(before.yaw+900))<.01f && Mathf.Abs(edit.TargetPitch-80)<.01f,"multiple horizontal turns remain unrestricted while upward pitch reaches 80 degrees");
                    for(int frame=0;frame<180;frame++) {
                        edit.RestoreFrame();edit.Step(1f/60);edit.ApplyFrame();
                        Check(Mathf.Abs(edit.Scale-before.scale)<.00001f && (edit.Translation-new Vector2(before.x,before.y)).sqrMagnitude<.000000001f,"single-finger rotation must never zoom or translate");
                        Check(Vector3.Distance(root.TransformPoint(pivotLocal),pivotWorld)<.00002f,"body rotation center stays exactly still");
                        Check(Mathf.Abs(edit.Pitch)<=80.001f,"displayed pitch never overshoots its boundary");
                    }
                    edit.End();edit.BeginAdjustment();edit.Move(0,2.5f);Tick(edit);
                    Check(Mathf.Abs(edit.Pitch+80)<.01f,"downward pitch reaches -80 degrees");
                    edit.End();edit.BeginAdjustment();edit.Move(0,-.05f);Tick(edit);
                    Check(edit.Pitch>-79 && edit.Pitch<0,"reversing at a limit responds immediately");
                    edit.Close();var saved=edit.Target;Tick(edit);
                    edit.RestoreFrame();edit.Load(saved,true);edit.ApplyFrame();Check(Near(edit.Current,saved),"reloaded free rotation keeps scale and translation");Check(!edit.Active && Near(edit.Current,saved),"close retains the latest view without explicit save");
                    ReviewPreview(edit,root);
                    camera.transform.position=cameraPosition+camera.transform.right*.3f;
                    edit.SetProjection(camera,region,safe);Tick(edit);
                    camera.transform.position=cameraPosition;edit.SetProjection(camera,region,safe);Tick(edit);
                    Check(Near(edit.Current,saved),"temporary launch/layout constraints do not overwrite saved intent");
                    edit.Begin(camera.transform.right);edit.ResetDraft();Tick(edit);Check(edit.Current.IsDefault,"reset exact default");
                    foreach(float yaw in new[]{-1080f,-450f,0f,450f,1080f})foreach(float pitch in new[]{-720f,-90f,0f,90f,720f})
                    foreach(float zoom in new[]{.78f,1.28f})foreach(float move in new[]{-.45f,.45f}) {
                        edit.Load(new CharacterViewPose{yaw=yaw,pitch=pitch,scale=zoom,x=move,y=-move});
                        for(int frame=0;frame<45;frame++) {
                            edit.RestoreFrame();edit.Step(1f/60);edit.ApplyFrame();
                            var neutral=edit.Current;neutral.yaw=neutral.pitch=0;
                            var projected=edit.Project(neutral);
                            Check(Mathf.Abs(edit.TargetYaw-yaw)<.01f && Mathf.Abs(edit.TargetPitch-Mathf.Clamp(Mathf.DeltaAngle(0,pitch),-80,80))<.01f,"saved yaw remains unrestricted and old pitch is normalized and clamped");
                            Check(projected.xMin>=safe.xMin-.0001f && projected.xMax<=safe.xMax+.0001f && projected.yMin>=safe.yMin-.0001f && projected.yMax<=safe.yMax+.0001f,
                                source.modelId+" "+size+" safe displayed corners "+projected+" vs "+safe);
                            Check(edit.Scale>=.4f && edit.Scale<=1.28f,"bounded scale");
                        }
                        var fitted=edit.Current;fitted.yaw=fitted.pitch=0;
                        Check(edit.Project(fitted).height>=safe.height*.3f,"portrait stays at least 30% of the safe viewport: "+source.modelId+" "+size+" "+edit.ProjectedEnvelope+" scale="+edit.Scale);
                    }
                    edit.Load(CharacterViewPose.Default);edit.Close();Tick(edit);
                    Check(edit.Current.IsDefault && root.position==position && root.localScale==scale && Quaternion.Angle(root.rotation,rotation)<.05f,"restore original root");
                    Check(camera.transform.position==cameraPosition,"model editing never changes camera");
                    for(int i=0;i<bones.Length;i++)Check(bones[i].localRotation==originals[i],"authored bone unchanged");
                    report.viewports.Add(source.modelId+" "+size);
                }
                edit.Bind(null);UnityEngine.Object.DestroyImmediate(instance);instance=null;
            }
            string directory=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/conversation-refinement");Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory,"runtime-review.json"),JsonUtility.ToJson(report,true)+"\n");
            Debug.Log("VIEW_EDITOR_REVIEW_PASS assertions="+report.assertions);
        } finally {edit.ResetImmediate();if(instance)UnityEngine.Object.DestroyImmediate(instance);UnityEngine.Object.DestroyImmediate(camera.gameObject);UnityEngine.Object.DestroyImmediate(hitHost);}
    }
}
