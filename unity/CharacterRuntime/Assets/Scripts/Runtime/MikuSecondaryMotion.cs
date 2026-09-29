using System;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    // Two short hair chains only. No mesh baking, rigidbodies, allocations or broad-phase physics per frame.
    [DefaultExecutionOrder(100)]
    public sealed class MikuSecondaryMotion : MonoBehaviour
    {
        sealed class Strand
        {
            public Transform bone,tip;
            public Vector3 point,velocity,target;
            public float length,radius;
        }
        struct Capsule { public Transform a,b; public float radius; }
        Strand[] strands;
        Capsule[] capsules;
        bool reset=true;
        public void ResetSimulation(){reset=true;}
        void OnEnable(){reset=true;}
        void OnApplicationPause(bool paused){reset=true;}
        void LateUpdate(){Step(Time.deltaTime);}
        void Initialize()
        {
            var named=new Dictionary<string,Transform>();foreach(var t in GetComponentsInChildren<Transform>(true))named[t.name]=t;
            var list=new List<Strand>();var colliders=new List<Capsule>();
            foreach(string side in new[]{"左","右"})
            {
                for(int j=2;j<=8;j++)
                {
                    var a=named[side+"髪"+(char)('０'+j)];var b=named[side+"髪"+(char)('０'+j+1)];
                    list.Add(new Strand{bone=a,tip=b,length=Vector3.Distance(a.position,b.position),radius=j<5?.19f:.16f});
                }
                colliders.Add(new Capsule{a=named[side+"腕"],b=named[side+"ひじ"],radius=.16f});
                colliders.Add(new Capsule{a=named[side+"ひじ"],b=named[side+"手首"],radius=.14f});
                colliders.Add(new Capsule{a=named[side+"足D"],b=named[side+"ひざD"],radius=.26f});
            }
            colliders.Add(new Capsule{a=named["腰"],b=named["上半身2"],radius=.52f});
            colliders.Add(new Capsule{a=named["上半身2"],b=named["首"],radius=.38f});
            strands=list.ToArray();capsules=colliders.ToArray();
        }
        public void Step(float dt)
        {
            if(strands==null)Initialize();
            if(dt<=0)return;
            if(dt>.1f)reset=true;dt=Mathf.Min(dt,1f/30);
            foreach(var s in strands)
            {
                s.target=s.tip.position;
                if(reset){s.point=s.target;s.velocity=Vector3.zero;}
            }
            reset=false;
            int steps=Mathf.Max(1,Mathf.CeilToInt(dt*120));float h=dt/steps;
            for(int step=0;step<steps;step++)foreach(var s in strands)
            {
                // Spring toward the authored silhouette; inertia is restrained to avoid whipping through the body.
                s.velocity+=(s.target-s.point)*(100*h);s.velocity*=Mathf.Exp(-17*h);s.point+=s.velocity*h;
            }
            foreach(var s in strands)
            {
                Vector3 origin=s.bone.position;
                var previous=s.point;
                for(int iteration=0;iteration<6;iteration++)
                {
                    s.point=origin+(s.point-origin).normalized*s.length;
                    foreach(var c in capsules)s.point=PushOut(s.point,c,s.radius);
                }
                s.point=origin+(s.point-origin).normalized*s.length;
                s.velocity+=(s.point-previous)*Mathf.Min(20,1/dt)*.15f;
                var from=s.tip.position-origin;var to=s.point-origin;
                if(from.sqrMagnitude>.00001f&&to.sqrMagnitude>.00001f)
                    s.bone.rotation=Quaternion.FromToRotation(from,to)*s.bone.rotation;
                s.point=s.tip.position;
            }
        }
        static Vector3 PushOut(Vector3 point,Capsule c,float radius)
        {
            Vector3 a=c.a.position,d=c.b.position-a;
            Vector3 closest=a+d*Mathf.Clamp01(Vector3.Dot(point-a,d)/Mathf.Max(.000001f,d.sqrMagnitude));
            Vector3 delta=point-closest;float length=delta.magnitude,min=c.radius+radius;
            if(length>=min)return point;
            return closest+(length>.0001f?delta/length:Vector3.back)*min;
        }
    }
}
