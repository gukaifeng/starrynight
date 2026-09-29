using System;
using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;

// Authored gestures baked against the actual rig. IK is an authoring operation, not a per-frame mobile cost.
public static class MikuMotionBuilder
{
    static float Ease(float t) { t=Mathf.Clamp01(t); return t*t*t*(t*(t*6-15)+10); }
    static float Pulse(float u,float enter=.22f,float exit=.77f)=>Ease(u/enter)*(1-Ease((u-exit)/(1-exit)));
    static Vector3 Blend(Vector3 a,Vector3 b,float w)=>Vector3.LerpUnclamped(a,b,w);
    public static AnimationClip Build(GameObject root,string action)
    {
        var ts=root.GetComponentsInChildren<Transform>(true);var named=ts.ToDictionary(t=>t.name,t=>t);
        var positions=ts.Select(t=>t.localPosition).ToArray();var rotations=ts.Select(t=>t.localRotation).ToArray();
        float duration=action switch {"Wave"=>3.6f,"Jump"=>2.3f,"Dance"=>5.6f,"Bow"=>3.5f,"Spin"=>4.2f,"Greet"=>3.8f,"Cheer"=>4.4f,"No"=>2.3f,_=>5f};
        var clip=new AnimationClip{name=action,legacy=true,frameRate=120,wrapMode=action=="Idle"?WrapMode.Loop:WrapMode.Once};
        var driven=new List<Transform>{named["Rig"],named["全ての親"],named["腰"],named["上半身"],named["上半身2"],named["頭"]};
        foreach(string side in new[]{"左","右"})
        {
            foreach(string part in new[]{"肩","腕","ひじ","手首","足D","ひざD","足首D"})driven.Add(named[side+part]);
            for(int j=1;j<=8;j++)driven.Add(named[side+"髪"+(char)('０'+j)]);
            foreach(string finger in new[]{"親指","人指","中指","薬指","小指"})for(int j=1;j<=3;j++)
                if(named.TryGetValue(side+finger+(char)('０'+j),out var t))driven.Add(t);
        }
        var curves=driven.ToDictionary(t=>t,t=>Enumerable.Range(0,7).Select(_=>new List<Keyframe>()).ToArray());
        var expression=Enumerable.Range(0,3).Select(_=>new List<Keyframe>()).ToArray();
        int count=Mathf.CeilToInt(duration*60);
        for(int frame=0;frame<=count;frame++)
        {
            for(int i=0;i<ts.Length;i++){ts[i].localPosition=positions[i];ts[i].localRotation=rotations[i];}
            float t=duration*frame/count,u=t/duration,p=Pulse(u),cycle=Mathf.Sin(t*2*Mathf.PI/1.4f);
            bool idle=action=="Idle";float breathe=Mathf.Sin(u*Mathf.PI*2);
            // Weight shift and chest counter-rotation; no rigid whole-body rocking.
            float sway=idle?.012f*breathe:action=="Dance"?.075f*cycle*p:action=="Wave"?-.03f*p:0;
            float crouch=idle?.009f*(1-Mathf.Cos(u*Mathf.PI*2)):0;
            float flight=0;
            if(action=="Jump")
            {
                crouch=-.18f*(Ease(u/.12f)-Ease((u-.20f)/.09f))-.11f*(Ease((u-.64f)/.08f)-Ease((u-.78f)/.20f));
                if(u>=.29f&&u<=.67f)flight=.48f*Mathf.Sin((u-.29f)/.38f*Mathf.PI);
            }
            if(action=="Dance")crouch=-.04f*p*(.5f+.5f*Mathf.Cos(t*2*Mathf.PI/1.4f));
            if(action=="Cheer")crouch=-.025f*p*(1+cycle);
            named["Rig"].localPosition=new Vector3(0,flight,0);
            named["腰"].localPosition+=new Vector3(sway,crouch-.035f,0);
            Rotate(named,"上半身",new Vector3(action=="Bow"?21*p:action=="Jump"?-crouch*35:1.1f*breathe,action=="Dance"?4*cycle*p:0,action=="Dance"?3*cycle*p:action=="Wave"?2*p:0));
            Rotate(named,"上半身2",new Vector3(action=="Bow"?5*p:0,action=="Dance"?-2*cycle*p:0,action=="Dance"?-1.5f*cycle*p:0));
            Rotate(named,"頭",new Vector3(action=="Bow"?8*p:action=="Greet"?4*p:0,
                action=="No"?15*Mathf.Sin((u-.2f)*Mathf.PI*4)*p:action=="Wave"?-5*p:0,
                idle?1.1f*breathe:action=="Wave"?-3*p:action=="Greet"?3*p:0));
            if(action=="Spin")Rotate(named,"全ての親",new Vector3(0,360*Ease((u-.12f)/.76f),0));
            Transform space=named["全ての親"];
            foreach(string jp in new[]{"左","右"})
            {
                float side=jp=="右"?1:-1;
                Vector3 hand=new Vector3(side*.74f,3.02f,.78f),target=hand;
                float move=p;
                if(action=="Wave"&&side>0)target=new Vector3(.91f+.09f*Mathf.Sin((u-.25f)*Mathf.PI*8),5.04f,.92f);
                if(action=="Jump") { target=new Vector3(side*1.08f,4.5f,.86f);move=Pulse(u,.43f,.62f); }
                if(action=="Dance")target=new Vector3(side*(.91f+.09f*Mathf.Sin(t*4.49f+side*.6f)),3.95f+.27f*Mathf.Sin(t*4.49f+side*1.2f),.99f+.10f*Mathf.Cos(t*4.49f+side));
                if(action=="Bow")target=new Vector3(side*.81f,2.98f,1.0f);
                if(action=="Spin")target=new Vector3(side*1.05f,3.8f,1.05f);
                if(action=="Greet")target=new Vector3(side*.64f,3.78f,1.18f);
                if(action=="Cheer")target=new Vector3(side*(1.05f+.05f*cycle),5.14f+.12f*cycle,.95f);
                hand=Blend(hand,target,move);hand.x+=sway;hand.y+=crouch;
                // Elbow pole remains outside the ribs and toward the front, away from the tails.
                Vector3 pole=new Vector3(side*1.65f,action=="Greet"?3.05f:action=="Dance"?3.45f:3.8f,1.0f);
                Solve(named[jp+"腕"],named[jp+"ひじ"],named[jp+"手首"],space.TransformPoint(hand),space.TransformPoint(pole));
                var wrist=named[jp+"手首"];
                wrist.localRotation=Quaternion.Euler(action=="Wave"&&side>0?6*Mathf.Sin(t*9)*p:0,action=="Greet"?side*22*p:0,side*5);
                // Keep feet planted while the pelvis yields; lift only during the turn's small steps.
                Vector3 foot=new Vector3(side*.277f,.202f,.121f);
                if(action=="Spin")foot.y+=.065f*p*Mathf.Max(0,Mathf.Sin(t*7+side*Mathf.PI/2));
                Solve(named[jp+"足D"],named[jp+"ひざD"],named[jp+"足首D"],space.TransformPoint(foot),space.TransformPoint(new Vector3(side*.3f,1.7f,2)));
                named[jp+"足首D"].rotation=space.rotation;
                foreach(string finger in new[]{"親指","人指","中指","薬指","小指"})for(int j=1;j<=3;j++)
                    if(named.TryGetValue(jp+finger+(char)('０'+j),out var f))
                        f.localRotation=Quaternion.Euler(0,0,side*(finger=="親指"?3:action=="Cheer"?12+14*p:6+j*2));
                for(int j=1;j<=8;j++)
                {
                    var h=named[jp+"髪"+(char)('０'+j)];
                    float lag=j*.24f;
                    h.localRotation=Quaternion.Euler((j==1&&action=="Bow"?-32*p:0)+.45f*Mathf.Sin(u*Mathf.PI*2-lag)*(idle?1:p),0,side*.35f*Mathf.Sin(u*Mathf.PI*2-lag)*(idle?1:p));
                }
            }
            foreach(var bone in driven)
            {
                var q=bone.localRotation;var keys=curves[bone];
                if(frame>0){var old=new Quaternion(keys[0][frame-1].value,keys[1][frame-1].value,keys[2][frame-1].value,keys[3][frame-1].value);if(Quaternion.Dot(old,q)<0)q=new Quaternion(-q.x,-q.y,-q.z,-q.w);}
                for(int a=0;a<4;a++)keys[a].Add(new Keyframe(t,q[a]));
                for(int a=0;a<3;a++)keys[4+a].Add(new Keyframe(t,bone.localPosition[a]));
            }
            float blink=100*(Ease((u-.56f)/.018f)-Ease((u-.588f)/.026f));
            expression[0].Add(new Keyframe(t,blink));expression[1].Add(new Keyframe(t,idle?18:18+22*p));expression[2].Add(new Keyframe(t,action=="Cheer"?15*p:0));
        }
        foreach(var bone in driven)
        {
            string path=AnimationUtility.CalculateTransformPath(bone,root.transform);
            for(int a=0;a<7;a++)Set(clip,path,typeof(Transform),a<4?"localRotation."+"xyzw"[a]:"localPosition."+"xyz"[a-4],curves[bone][a]);
        }
        for(int i=0;i<3;i++)Set(clip,"Head",typeof(SkinnedMeshRenderer),"blendShape."+new[]{"Blink","Smile","OpenMouth"}[i],expression[i]);
        clip.EnsureQuaternionContinuity();
        for(int i=0;i<ts.Length;i++){ts[i].localPosition=positions[i];ts[i].localRotation=rotations[i];}
        return clip;
    }
    static void Rotate(Dictionary<string,Transform> named,string name,Vector3 euler)=>named[name].localRotation=Quaternion.Euler(euler);
    static void Set(AnimationClip clip,string path,Type type,string property,List<Keyframe> keys)
    {
        if(keys.All(k=>Mathf.Abs(k.value-keys[0].value)<.000001f))keys=new List<Keyframe>{keys[0],keys[keys.Count-1]};
        var curve=new AnimationCurve(keys.ToArray());for(int i=0;i<curve.length;i++)curve.SmoothTangents(i,0);clip.SetCurve(path,type,property,curve);
    }
    public static void Solve(Transform upper,Transform middle,Transform end,Vector3 target,Vector3 pole)
    {
        Vector3 a=upper.position,b=middle.position,c=end.position;float l1=(b-a).magnitude,l2=(c-b).magnitude;
        Vector3 delta=target-a;float distance=Mathf.Clamp(delta.magnitude,Mathf.Abs(l1-l2)+.001f,l1+l2-.0002f);Vector3 direction=delta.normalized;
        Vector3 bend=Vector3.ProjectOnPlane(pole-a,direction).normalized;
        float along=(l1*l1+distance*distance-l2*l2)/(2*distance);float height=Mathf.Sqrt(Mathf.Max(0,l1*l1-along*along));
        Vector3 elbow=a+direction*along+bend*height;
        upper.rotation=Quaternion.FromToRotation(b-a,elbow-a)*upper.rotation;
        middle.rotation=Quaternion.FromToRotation(end.position-middle.position,target-middle.position)*middle.rotation;
    }
}
