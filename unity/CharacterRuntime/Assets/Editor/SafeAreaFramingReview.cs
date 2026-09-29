using System;
using System.Collections.Generic;
using System.IO;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;

// Content validation uses the authored meshes plus Unity's own projection as the
// oracle. These are test windows, never a device whitelist used by the runtime.
public static class SafeAreaFramingReview
{
    [Serializable] class Window
    {
        public string name; public float width,height,top,left,right,bottom;
        public Rect Safe => new Rect((left+8)/width,bottom/height,
            (width-left-right-16)/width,1-(top+10+bottom)/height);
    }
    [Serializable] class Result
    {
        public string model,window; public int projections,transitionSamples;
        public float minimumTopClearance,maximumDistanceChange;
    }
    [Serializable] class Report
    {
        public string result="passed"; public int safeFramingRevision=1;
        public Window[] windows; public Result[] cases;
    }
    static void Require(bool condition,string message) { if(!condition) throw new Exception("Safe-area framing: "+message); }
    public static void Validate()
    {
        const string scene="Assets/Scenes/ViewerScene.unity";
        var windows=new[] {
            new Window {name="island-portrait",width=402,height=874,top=62,bottom=34},
            new Window {name="notch-portrait",width=375,height=812,top=44,bottom=34},
            new Window {name="compact-no-cutout",width=375,height=667,top=20},
            new Window {name="cutout-landscape",width=874,height=402,left=62,right=62,bottom=21}
        };
        EditorSceneManager.OpenScene(scene);
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var camera=viewer.viewCamera;
        var results=new List<Result>();
        try
        {
            Require(viewer.characters.Length>=10,"expected the complete ten-character catalog");
            foreach(var character in viewer.characters)
            {
                foreach(var other in viewer.characters) other.gameObject.SetActive(other==character);
                var animation=character.GetComponentInChildren<Animation>(true);
                animation.GetClip("Idle").SampleAnimation(character.gameObject,0);
                var rest=character.RestBounds();
                Require(rest.size.y>0 && float.IsFinite(rest.max.y),"invalid rest bounds for "+character.modelId);
                foreach(var window in windows)
                {
                    camera.aspect=window.width/window.height;
                    var result=new Result {model=character.modelId,window=window.name,minimumTopClearance=float.PositiveInfinity};
                    foreach(string shot in new[] {"conversation","full"})
                    foreach(float size in new[] {.9f,1f,1.1f})
                    foreach(float angle in new[] {-20f,0f,20f})
                    {
                        var region=FramingMath.Region(rest,shot,false,character.conversationStart);
                        var rotation=FramingMath.Rotation(angle);
                        float distance=FramingMath.Distance(region,rotation,camera.aspect,camera.fieldOfView,size,camera.nearClipPlane);
                        var focus=FramingMath.ImmersiveFocus(region,rest,character.conversationStart,rotation,camera.aspect,camera.fieldOfView,distance);
                        float before=distance;
                        FramingMath.ConstrainSafeFrame(region,rotation,camera.aspect,camera.fieldOfView,window.Safe,ref focus,ref distance);
                        result.maximumDistanceChange=Mathf.Max(result.maximumDistanceChange,Mathf.Abs(before-distance));
                        if(window.width<window.height) Require(Mathf.Abs(before-distance)<.0001f,"portrait changed user zoom");
                        var first=new CameraFramingMotion(); first.SetTarget(focus,distance,FramingMath.Pitch); first.Snap();
                        camera.transform.SetPositionAndRotation(first.Focus-rotation*Vector3.forward*first.Distance,rotation);
                        CheckProjection(camera,region,window.Safe,result);
                        var sameFocus=focus; float sameDistance=distance;
                        FramingMath.ConstrainSafeFrame(region,rotation,camera.aspect,camera.fieldOfView,window.Safe,ref sameFocus,ref sameDistance);
                        Require(Vector3.Distance(sameFocus,focus)<.00002f && Mathf.Abs(sameDistance-distance)<.00002f,"repeat layout drift");
                        Require(first.Settled,"first visible frame not final");
                    }
                    // Direct yaw motion plus a layout spring is constrained at every visible
                    // frame, including the transient pose and overshoot, rather than endpoints.
                    var portrait=FramingMath.Region(rest,"conversation",false,character.conversationStart);
                    var motion=new CameraFramingMotion();
                    for(int frame=0;frame<240;frame++)
                    {
                        var rotation=FramingMath.Rotation(20*Mathf.Sin(frame/239f*Mathf.PI*2));
                        float distance=FramingMath.Distance(portrait,rotation,camera.aspect,camera.fieldOfView,1.1f,camera.nearClipPlane);
                        var focus=FramingMath.ImmersiveFocus(portrait,rest,character.conversationStart,rotation,camera.aspect,camera.fieldOfView,distance);
                        FramingMath.ConstrainSafeFrame(portrait,rotation,camera.aspect,camera.fieldOfView,window.Safe,ref focus,ref distance);
                        motion.SetTarget(focus,distance,FramingMath.Pitch);
                        if(frame==0) motion.Snap(); else motion.Step(1f/120,CameraFramingMotion.ControlResponse);
                        focus=motion.Focus; distance=motion.Distance;
                        FramingMath.ConstrainSafeFrame(portrait,rotation,camera.aspect,camera.fieldOfView,window.Safe,ref focus,ref distance);
                        camera.transform.SetPositionAndRotation(focus-rotation*Vector3.forward*distance,rotation);
                        CheckProjection(camera,portrait,window.Safe,result); result.transitionSamples++;
                    }
                    results.Add(result);
                }
            }
            Require(FramingMath.SafeFrame(float.NaN,0,1,1)==new Rect(0,0,1,1),"malformed safe frame fallback");
            string directory=Path.GetFullPath("../../.local/checks/safe-area-framing"); Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory,"projection-audit.json"),JsonUtility.ToJson(new Report {windows=windows,cases=results.ToArray()},true));
            Debug.Log("SAFE_AREA_FRAMING_PASS "+results.Count+" model/window cases; user zoom, all corner projections, first final frame, repeated-layout stability and 120 Hz yaw transitions.");
        }
        finally { EditorSceneManager.OpenScene(scene); }
    }
    static void CheckProjection(Camera camera,Bounds region,Rect safe,Result result)
    {
        // Call Unity's camera projection directly, independently of the frustum solver.
        for(int corner=0;corner<8;corner++)
        {
            Vector3 point=camera.WorldToViewportPoint(FramingMath.Corner(region,corner));
            Require(point.z>camera.nearClipPlane,"point behind near plane");
            Require(point.x>=safe.xMin-.00002f && point.x<=safe.xMax+.00002f && point.y<=safe.yMax+.00002f,
                result.model+" "+result.window+" crosses safe area: "+point);
            result.minimumTopClearance=Mathf.Min(result.minimumTopClearance,safe.yMax-point.y);
            result.projections++;
        }
    }
}
