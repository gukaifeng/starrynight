using System;
using System.IO;
using System.Collections.Generic;
using ModelSpace;
using UnityEngine;
using UnityEditor.SceneManagement;

public static class AmbientPortraitReview
{
    [Serializable] class Measurement {public string model,window,method;public float height,faceY,faceFraction,top,distance,travel;}
    [Serializable] class Report {public string status="PASS";public int assertions;public List<Measurement> portraits=new List<Measurement>();}
    static Report report;
    static void Check(bool ok,string detail){if(!ok)throw new Exception("AMBIENT_PORTRAIT: "+detail);report.assertions++;}
    public static void SetupAndRun(){BuildIos.Setup();Run();}
    public static void Run()
    {
        report=new Report();
        foreach(int hz in new[]{30,60,120}) foreach(bool speaking in new[]{false,true})
        {
            var turn=new CharacterAmbientTurn();turn.Reset(123);
            bool left=false,right=false,up=false,down=false;
            for(int i=0;i<hz*120;i++) {
                turn.Step(1f/hz,true,speaking);var p=turn.Offset;
                Check(Mathf.Abs(p.x)<(speaking?3.21f:6.51f) && Mathf.Abs(p.y)<(speaking?1.31f:2.61f),"bounded random turn at "+hz);
                left|=p.x<-.7f;right|=p.x>.7f;up|=p.y>.3f;down|=p.y<-.3f;
            }
            Check(left && right && up && down && turn.Waypoints>12,"intermittent multidirectional movement");
            for(int i=0;i<hz*3;i++)turn.Step(1f/hz,false,speaking);
            Check(turn.Offset==Vector2.zero && turn.Suppressed,"manual control releases ambient exactly");
        }
        var preview=new CharacterPreviewRotation();preview.Begin();
        bool reactedWhileDown=false;
        for(int i=0;i<120;i++) {preview.Move(.08f*Mathf.Sin(i/59f*Mathf.PI*3),0);preview.Step(1f/60);reactedWhileDown|=preview.Active && preview.ShakeCount==1;}
        Check(reactedWhileDown,"shake reacts before lift");Check(!preview.End(true) && preview.ShakeCount==1,"release does not double emit");
        preview.Begin();for(int i=0;i<120;i++){preview.Move(.1f*Mathf.Sin(i*.2f),0);preview.Step(1f/60);}
        Check(preview.ShakeCount==1,"continued dragging is cooled down");
        preview.Reset();preview.Begin();preview.Move(.1f,0);for(int i=0;i<120;i++)preview.Step(1f/60);
        Check(preview.ShakeCount==0,"one way turn is not shaking");
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();var camera=viewer.viewCamera;
        string output=CharacterPackageBuilder.Root+"/.local/checks/ambient-portrait";Directory.CreateDirectory(output);
        foreach(var character in viewer.characters) {
            foreach(var other in viewer.characters)other.gameObject.SetActive(other==character);
            character.GetComponentInChildren<Animation>(true).GetClip("Idle").SampleAnimation(character.gameObject,0);
            var portrait=character.portrait;Check(portrait!=null && portrait.localFaceHeight>0,"calibration exists: "+character.modelId);
            var root=character.transform;var edit=new CharacterInspectionRotation();edit.Bind(root);
            var region=portrait.Region(root);var face=portrait.Face(root);float faceHeight=portrait.FaceHeight(root);
            foreach(var size in new[]{new Vector2(375,667),new Vector2(393,852),new Vector2(402,874),new Vector2(440,956)}) {
                camera.aspect=size.x/size.y;var rotation=FramingMath.Rotation(0);
                var safe=new Rect(8/size.x,34/size.y,1-16/size.x,1-(34+72)/size.y);
                portrait.Compose(root,rotation,camera.aspect,camera.fieldOfView,1,camera.nearClipPlane,out var focus,out float distance);
                edit.ComposePortrait(region,face,rotation,camera.aspect,camera.fieldOfView,safe,ref focus,ref distance);
                edit.ConstrainComposition(region,rotation,camera.aspect,camera.fieldOfView,safe,ref focus,ref distance);
                camera.transform.SetPositionAndRotation(focus-rotation*Vector3.forward*distance,rotation);
                float faceY=camera.WorldToViewportPoint(face).y;
                float fraction=camera.WorldToViewportPoint(face+Vector3.up*faceHeight*.5f).y-camera.WorldToViewportPoint(face-Vector3.up*faceHeight*.5f).y;
                var projected=FramingMath.ProjectedBounds(region,camera);
                Check(faceY>.59f && faceY<.65f && fraction>.12f && fraction<.35f,"visible face: "+character.modelId+" "+faceY+" "+fraction);
                var again=focus;var d=distance;edit.ConstrainComposition(region,rotation,camera.aspect,camera.fieldOfView,safe,ref again,ref d);
                Check(Vector3.Distance(again,focus)<.0001f && Mathf.Abs(d-distance)<.0001f,"stable repeated layout");
                edit.SetProjection(camera,region,safe);var saved=edit.Target;
                for(int i=0;i<1200;i++){edit.RestoreFrame();edit.Step(1f/60);edit.Ambient.Step(1f/60,true,false);edit.ApplyFrame();}
                Check(edit.Target.IsDefault && edit.Current.IsDefault && edit.Preview.ShakeCount==0,"ambient does not save pose or trigger shake");
                report.portraits.Add(new Measurement{model=character.modelId,window=size.ToString(),method=portrait.measurement,
                    height=character.RestBounds().size.y,faceY=faceY,faceFraction=fraction,top=projected.yMax,distance=distance,travel=edit.Ambient.Travel});
                edit.RestoreFrame();
                if(size.x==402) {PortraitRefinementReview.Render(camera,output+"/"+character.modelId+".png",804,1748);PortraitRefinementReview.Render(camera,output+"/"+character.modelId+".png",804,1748);}
                edit.ResetImmediate();
            }
            edit.Bind(null);
        }
        File.WriteAllText(output+"/review.json",JsonUtility.ToJson(report,true));
        Debug.Log("AMBIENT_PORTRAIT_PASS assertions="+report.assertions+" portraits="+report.portraits.Count);
    }
}
