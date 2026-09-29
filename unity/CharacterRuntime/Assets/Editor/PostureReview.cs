using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;
using ModelSpace;
public static class PostureReview
{
    [Serializable] sealed class ContactAudit { public string status="PASS"; public int samples;public float minY;public List<string> penetrations=new List<string>(); }
    public static void AuditTransitions()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();var report=new ContactAudit();
        foreach(var c in viewer.characters.Where(c=>c.Manifest.posture!=null && c.Manifest.posture.poses.Length>0))
        {
            foreach(var other in viewer.characters)other.gameObject.SetActive(other==c);
            var bones=c.Manifest.posture.bones.Select(p=>c.transform.Find(p)).ToArray();var player=c.GetComponent<Animation>();
            foreach(var from in c.Manifest.posture.poses) foreach(var to in c.Manifest.posture.poses)
            {
                if(from==to)continue;
                player.GetClip(from.clip).SampleAnimation(c.gameObject,0);var a=bones.Select(t=>t.localPosition).ToArray();var ar=bones.Select(t=>t.localRotation).ToArray();
                player.GetClip(to.clip).SampleAnimation(c.gameObject,0);var b=bones.Select(t=>t.localPosition).ToArray();var br=bones.Select(t=>t.localRotation).ToArray();
                float min=0;
                for(int frame=0;frame<=20;frame++)
                {
                    var guard=c.GetComponent<PostureGrounding>();if(guard)guard.Restore();
                    float u=frame/20f,t=u*u*u*(u*(u*6-15)+10);
                    for(int j=0;j<bones.Length;j++){bones[j].localPosition=Vector3.Lerp(a[j],b[j],t);bones[j].localRotation=Quaternion.Slerp(ar[j],br[j],t);}
                    if(guard)guard.Apply();min=Mathf.Min(min,BakedBounds(c).min.y);if(guard)guard.Restore();report.samples++;
                }
                report.minY=Mathf.Min(report.minY,min);
                if(min<-.025f)report.penetrations.Add(c.modelId+" "+from.id+" -> "+to.id+" minY="+min);
            }
        }
        if(report.penetrations.Count>0)report.status="NEEDS_CONTACT_GUARD";
        File.WriteAllText(Path.Combine(CharacterPackageBuilder.Root,"docs/verification/posture/transition-contact-audit.json"),JsonUtility.ToJson(report,true));
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
    }
    public static void Capture()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var camera=viewer.viewCamera;camera.aspect=1;
        string folder=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/posture/engine");Directory.CreateDirectory(folder);
        var rows=new List<string>();
        foreach(var character in viewer.characters.Where(c=>c.Manifest.posture!=null && c.Manifest.posture.poses.Length>0))
        {
            foreach(var other in viewer.characters)other.gameObject.SetActive(other==character);
            var studio=viewer.GetComponent<CharacterStudioDriver>();studio.Bind(character);studio.Configure(new StudioSettings());
            var player=character.GetComponent<Animation>();
            foreach(var pose in character.Manifest.posture.poses)
            {
                player.GetClip(pose.clip).SampleAnimation(character.gameObject,0);
                var bounds=BakedBounds(character);
                rows.Add(character.modelId+"/"+pose.id+" minY="+bounds.min.y+" size="+bounds.size);
                camera.transform.rotation=FramingMath.Rotation(-12);
                float distance=FramingMath.Distance(bounds,camera.transform.rotation,1,camera.fieldOfView,.95f,camera.nearClipPlane);
                camera.transform.position=bounds.center-camera.transform.forward*distance;
                CharacterVisualReview.Render(camera,Path.Combine(folder,character.modelId+"-"+pose.id+".png"),900);
            }
            player.GetClip("Idle").SampleAnimation(character.gameObject,0);
        }
        File.WriteAllLines(Path.Combine(folder,"bounds.txt"),rows);
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
    }
    public static Bounds BakedBounds(ViewerCharacter c)
    {
        var mesh=new Mesh();var bounds=new Bounds();bool first=true;
        foreach(var r in c.GetComponentsInChildren<Renderer>())
        {
            Mesh current;
            if(r is SkinnedMeshRenderer skin){skin.BakeMesh(mesh,true);current=mesh;}
            else current=r.GetComponent<MeshFilter>()?.sharedMesh;
            if(!current)continue;
            foreach(var p in current.vertices)
            {
                var world=r.transform.TransformPoint(p);
                if(first){bounds=new Bounds(world,Vector3.zero);first=false;}else bounds.Encapsulate(world);
            }
        }
        UnityEngine.Object.DestroyImmediate(mesh);return bounds;
    }
    public static void Runtime()
    {
        if(!EditorApplication.isPlaying)throw new Exception("Play Mode required");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();int presentation=400,assertions=0;
        void Check(bool ok,string message){if(!ok)throw new Exception("POSTURE_REVIEW_FAILED: "+message);assertions++;}
        foreach(var character in viewer.characters)
        {
            viewer.ReceiveCommand(JsonUtility.ToJson(new BridgeCommand {schemaVersion=1,kind="command",name="selectModel",presentationId=presentation++,payload=new BridgePayload{modelId=character.modelId}}));
            var director=viewer.GetComponent<CharacterDirector>();var posture=viewer.GetComponent<CharacterPosture>();var actions=viewer.GetComponent<CharacterActions>();
            int sequence=0;
            CharacterSignal Signal(PostureRequest p)=>new CharacterSignal{apiMinor=1,actorId=character.modelId,eventName="posture.set",eventId="posture-review-"+(++sequence),sequence=sequence,posture=p};
            var invalid=director.Receive(Signal(new PostureRequest{id="future.unknown"}));Check(invalid.status=="rejected","unknown pose rejected");
            if(!posture.State.supported){Check(posture.State.id=="stand","legacy stand remains");continue;}
            foreach(var pose in character.Manifest.posture.poses)
            {
                var receipt=director.Receive(Signal(new PostureRequest{id=pose.id}));Check(receipt.status=="accepted",pose.id+" accepted");
                Check(posture.State.id==pose.id,"persistent id");
                if(posture.State.transitioning)Check(!actions.CanPlay("Wave"),"transition protects body channel");
                var p=pose.parameters.FirstOrDefault();
                if(p!=null)
                {
                    Check(director.Receive(Signal(new PostureRequest{id=pose.id,parameters=new[]{new CharacterParameterValue{id=p.id,value=p.max+1}}})).code=="POSTURE_PARAMETER_RANGE","range rejected atomically");
                    Check(director.Receive(Signal(new PostureRequest{id=pose.id,parameters=new[]{new CharacterParameterValue{id=p.id,value=float.NaN}}})).status=="rejected","NaN rejected");
                }
                Check(director.Receive(Signal(new PostureRequest{id=pose.id,parameters=new[]{new CharacterParameterValue{id="unknown",value=0}}})).code=="POSTURE_PARAMETER_UNKNOWN","unknown parameter");
                director.Local("turn.cancel");Check(posture.State.id==pose.id,"turn cancellation preserves posture");
                Check(actions.FramingClip==pose.clip,"return action goes to pose clip");
            }
        }
        string file=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/posture/engine-review.json");Directory.CreateDirectory(Path.GetDirectoryName(file));File.WriteAllText(file,"{\"status\":\"PASS\",\"assertions\":"+assertions+"}");
    }
}
