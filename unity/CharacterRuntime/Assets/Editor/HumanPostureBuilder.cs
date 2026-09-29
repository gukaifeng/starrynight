using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using ModelSpace;

// Reference authoring adapter. External packages supply the same clips in GLB.
public static class HumanPostureBuilder
{
    public static void Build(GameObject root)
    {
        var manifest=JsonUtility.FromJson<CharacterManifest>(File.ReadAllText(Path.Combine(CharacterPackageBuilder.Root,"character-packages/builtins/real-woman/character.json")));
        var player=root.GetComponent<Animation>();
        player.GetClip("Idle").SampleAnimation(root,0);
        var all=root.GetComponentsInChildren<Transform>(true);
        var positions=all.Select(t=>t.localPosition).ToArray();var rotations=all.Select(t=>t.localRotation).ToArray();
        var names=all.ToDictionary(t=>t.name,t=>t);
        var bones=manifest.posture.bones.Select(p=>root.transform.Find(p)).ToArray();
        void Reset() { for(int i=0;i<all.Length;i++){all[i].localPosition=positions[i];all[i].localRotation=rotations[i];} }
        foreach(var pose in manifest.posture.poses)
        {
            Create(pose.clip,pose,null,0,"");
            foreach(var p in pose.parameters) {Create(p.lowClip,pose,p.id,p.min,"");Create(p.highClip,pose,p.id,p.max,"");}
            foreach(var a in pose.actions) Create(a.clip,pose,null,0,a.action);
        }
        Reset();player.GetClip("Idle").SampleAnimation(root,0);
        void Create(string clipName,PostureDefinition pose,string parameter,float value,string action)
        {
            float duration=string.IsNullOrEmpty(action)?4:3.2f;int count=parameter!=null?1:120;
            var curves=bones.ToDictionary(b=>b,b=>Enumerable.Range(0,7).Select(_=>new List<Keyframe>()).ToArray());
            float floorOffset=0;
            for(int step=0;step<=count;step++)
            {
                Reset();float u=(float)step/count,time=u*duration;
                float Read(string id) => parameter==id?value:Array.Find(pose.parameters,p=>p.id==id)?.initial ?? 0;
                Apply(root.transform,names,pose.id,Read("lean"),Read("legRoom"),Read("armRoom"),time,action);
                float yaw=Read("turn");
                var pivot=names["Root"];pivot.rotation=Quaternion.AngleAxis(yaw,Vector3.up)*pivot.rotation;
                if(step==0) floorOffset=Mathf.Max(0,.006f-Lowest(root));
                pivot.position+=Vector3.up*floorOffset;
                foreach(var b in bones)
                {
                    var q=b.localRotation;var c=curves[b];
                    if(step>0 && Quaternion.Dot(new Quaternion(c[3][step-1].value,c[4][step-1].value,c[5][step-1].value,c[6][step-1].value),q)<0) q=new Quaternion(-q.x,-q.y,-q.z,-q.w);
                    for(int axis=0;axis<3;axis++) c[axis].Add(new Keyframe(time,b.localPosition[axis]));
                    for(int axis=0;axis<4;axis++) c[axis+3].Add(new Keyframe(time,q[axis]));
                }
            }
            var clip=new AnimationClip {name=clipName,legacy=true,frameRate=30,wrapMode=string.IsNullOrEmpty(action)?WrapMode.Loop:WrapMode.ClampForever};
            foreach(var bone in bones) for(int axis=0;axis<7;axis++)
                clip.SetCurve(AnimationUtility.CalculateTransformPath(bone,root.transform),typeof(Transform),axis<3?"localPosition."+"xyz"[axis]:"localRotation."+"xyzw"[axis-3],new AnimationCurve(curves[bone][axis].ToArray()));
            clip.EnsureQuaternionContinuity();string path="Assets/RealCharacter/"+clipName+".anim";
            var old=AssetDatabase.LoadAssetAtPath<AnimationClip>(path);
            if(old){EditorUtility.CopySerialized(clip,old);UnityEngine.Object.DestroyImmediate(clip);clip=old;}else AssetDatabase.CreateAsset(clip,path);
            player.AddClip(clip,clipName);if(clipName=="Idle")player.clip=clip;
        }
    }
    static void Apply(Transform root,Dictionary<string,Transform> n,string pose,float lean,float legRoom,float armRoom,float time,string action)
    {
        var pelvis=n["pelvis"];var spine=n["spine_01"];var pivot=n["Root"];
        bool sit=pose=="sit",crouch=pose=="crouch",lie=pose=="lie";
        var footRotations=new[]{n["foot_l"].rotation,n["foot_r"].rotation};
        var handRotations=new[]{n["hand_l"].rotation,n["hand_r"].rotation};
        var p=root.InverseTransformPoint(pelvis.position);
        if(sit)p=new Vector3(0,.13f,-.13f);
        if(crouch)p=new Vector3(0,.33f,-.13f);
        pelvis.position=root.TransformPoint(p);
        spine.rotation=Quaternion.AngleAxis(lean+(crouch?22:sit?4:0),root.right)*spine.rotation;
        n["spine_02"].rotation=Quaternion.AngleAxis(.45f*Mathf.Sin(time*Mathf.PI/2),root.right)*n["spine_02"].rotation;
        for(int side=0;side<2;side++)
        {
            string suffix=side==0?"l":"r";float sign=side==0?-1:1;
            float spread=Mathf.Lerp(.12f,.22f,legRoom);
            Vector3 target=new Vector3(sign*spread,.08f,sit?.49f:crouch?.12f:0);
            if(lie)target=new Vector3(side==0?.06f:.10f,side==0?.26f:.14f,side==0?.24f+legRoom*.16f:.12f);
            Solve(n["thigh_"+suffix],n["calf_"+suffix],n["foot_"+suffix],root.TransformPoint(target),root.TransformPoint(new Vector3(sign*(spread+.08f),.5f,.8f)));
            n["foot_"+suffix].rotation=footRotations[side];
            Vector3 hand=sit?new Vector3(sign*(spread+.035f),.38f,.33f):crouch?new Vector3(sign*(spread+.045f),.35f,.36f):new Vector3(sign*.24f,.72f,.07f);
            hand.x+=sign*armRoom*.075f;
            if(lie)hand=side==0?new Vector3(-.02f-armRoom*.06f,.94f,.23f):new Vector3(.16f,1.40f,.12f);
            float pulse=Mathf.SmoothStep(0,1,time/.8f)*(1-Mathf.SmoothStep(0,1,(time-2.4f)/.8f));
            if((action=="Wave" || action=="Greet") && suffix=="r") hand=Vector3.Lerp(hand,new Vector3(.34f,pelvis.position.y+.52f,.22f),pulse);
            var elbow=lie ? new Vector3(side==0?-.22f:.12f,1.15f,side==0?.08f:.65f) : new Vector3(sign*.6f,pelvis.position.y+.2f,.15f);
            Solve(n["upperarm_"+suffix],n["lowerarm_"+suffix],n["hand_"+suffix],root.TransformPoint(hand),root.TransformPoint(elbow));
            n["hand_"+suffix].rotation=handRotations[side];
            if(action=="No")n["HeadPivot"].rotation=Quaternion.AngleAxis(9*Mathf.Sin(time*5.8f)*pulse,root.up)*n["HeadPivot"].rotation;
            if(action=="Bow")n["HeadPivot"].rotation=Quaternion.AngleAxis(4*pulse,root.right)*n["HeadPivot"].rotation;
            if(action=="Wave" && suffix=="r")n["hand_r"].localRotation*=Quaternion.Euler(0,0,9*Mathf.Sin(time*8)*pulse);
        }
        if(lie)
        {
            // Side rest: roll the whole rig, preserving its forward-facing facial basis.
            var point=pelvis.position;
            pivot.RotateAround(point,root.forward,-88);
            var center=root.InverseTransformPoint(pelvis.position);
            pivot.position+=root.TransformVector(new Vector3(-center.x,.14f-center.y,-center.z));
        }
    }
    static float Lowest(GameObject root)
    {
        var baked=new Mesh();float y=float.PositiveInfinity;
        foreach(var skin in root.GetComponentsInChildren<SkinnedMeshRenderer>())
        {
            skin.BakeMesh(baked,true);
            foreach(var v in baked.vertices)y=Mathf.Min(y,skin.transform.TransformPoint(v).y);
        }
        UnityEngine.Object.DestroyImmediate(baked);return y;
    }
    static void Solve(Transform a,Transform b,Transform c,Vector3 target,Vector3 pole)
    {
        Vector3 av=a.position,bv=b.position,cv=c.position;
        float l1=Vector3.Distance(av,bv),l2=Vector3.Distance(bv,cv),d=Mathf.Clamp(Vector3.Distance(target,av),Mathf.Abs(l1-l2)+.001f,l1+l2-.001f);
        Vector3 direction=(target-av).normalized,bend=Vector3.ProjectOnPlane(pole-av,direction).normalized;
        float along=(l1*l1+d*d-l2*l2)/(2*d),height=Mathf.Sqrt(Mathf.Max(0,l1*l1-along*along));
        a.rotation=Quaternion.FromToRotation(bv-av,direction*along+bend*height)*a.rotation;
        b.rotation=Quaternion.FromToRotation(c.position-b.position,target-b.position)*b.rotation;
    }
}
