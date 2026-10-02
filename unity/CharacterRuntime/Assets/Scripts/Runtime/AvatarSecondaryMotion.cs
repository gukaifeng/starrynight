using System;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class SecondaryStrandData { public string bone,tip,wind; public string[] colliderIDs,chainIDs; public bool initialEnabled=true;public float radius=.01f,angle=16,windResponse=1; }
    [Serializable] public sealed class SecondaryColliderData { public string bone,id; public Vector3 offset; public float radius; public bool localRadius; }
    [Serializable] public sealed class SecondaryPlaneData { public string bone,id; public Vector3 offset,normal; }
    [Serializable] public sealed class SecondaryPhysicsBinding {public string id,kind;public bool enabled;}
    [Serializable] public sealed class SecondaryPhysicsControl {public string option,kind;public SecondaryPhysicsBinding[] on,off;}
    [Serializable] public sealed class SecondaryMotionData
    {
        public int schemaVersion;
        public float ambientHairAngle=2.2f;
        public float ambientClothAngle;
        public SecondaryStrandData[] strands;
        public SecondaryColliderData[] colliders;
        public SecondaryPlaneData[] planes=Array.Empty<SecondaryPlaneData>();
        public SecondaryPhysicsControl[] controls=Array.Empty<SecondaryPhysicsControl>();
    }

    // Bounded secondary motion, using the source VRM's hair chains and collider
    // spheres. Springs run after animation/gaze; invisible characters do no work.
    // This is a small extension of the project's Miku spring solver, not a full
    // cloth simulation. It deliberately preserves the artist's silhouette.
    [DefaultExecutionOrder(110)]
    public sealed class AvatarSecondaryMotion : MonoBehaviour
    {
        public const float MaxHairAngle=8,MaxClothAngle=4;
        [Serializable] public sealed class Strand
        {
            public Transform bone,tip;
            public float radius,angle;
            public string wind;
            public float windResponse=1;
            public string[] colliderIDs;
            public string[] chainIDs;
            public bool initialEnabled=true,enabled=true;
            [NonSerialized] public bool desiredEnabled;
            public Quaternion rest;
            [NonSerialized] public Vector3 point,velocity;
            [NonSerialized] public Quaternion animatedRotation;
            [NonSerialized] public bool airClassified,isHair,poseCaptured;
            [NonSerialized] public float airResponse;
        }
        [Serializable] public sealed class Sphere
        {
            public Transform bone;
            public Vector3 offset;
            public float radius;
            public bool localRadius;
            public string id;
            public bool enabled=true;
        }
        [Serializable] public sealed class Plane {public Transform bone;public string id;public Vector3 offset,normal;public bool enabled=true;}
        public Strand[] strands=Array.Empty<Strand>();
        public Sphere[] colliders=Array.Empty<Sphere>();
        public Plane[] planes=Array.Empty<Plane>();
        public SecondaryPhysicsControl[] controls=Array.Empty<SecondaryPhysicsControl>();
        public void ApplyControls(CharacterPerformanceDriver driver)
        {
            if(controls.Length==0)return;
            foreach(var strand in strands)strand.desiredEnabled=strand.initialEnabled;
            foreach(var sphere in colliders)sphere.enabled=true;
            foreach(var plane in planes)plane.enabled=true;
            foreach(var control in controls)
            {
                bool selected=driver && driver.SelectionActive(control.option);
                var bindings=selected?control.on:control.kind=="toggle"?control.off:Array.Empty<SecondaryPhysicsBinding>();
                foreach(var binding in bindings)
                {
                    if(binding.kind=="chain")foreach(var strand in strands)
                    {if(strand.chainIDs!=null && Array.IndexOf(strand.chainIDs,binding.id)>=0)strand.desiredEnabled=binding.enabled;}
                    else
                    {
                        foreach(var sphere in colliders)if(sphere.id==binding.id)sphere.enabled=binding.enabled;
                        foreach(var plane in planes)if(plane.id==binding.id)plane.enabled=binding.enabled;
                    }
                }
            }
            foreach(var strand in strands)SetEnabled(strand,strand.desiredEnabled);
        }
        static void SetEnabled(Strand strand,bool value)
        {
            if(strand.enabled!=value && strand.tip){strand.point=strand.tip.position;strand.velocity=Vector3.zero;}
            strand.enabled=value;
        }
        static bool Applies(Strand strand,string id) => strand.colliderIDs==null || Array.IndexOf(strand.colliderIDs,id)>=0;
        // Ambient air is a small spring force, not a transform animation. Its
        // scale follows each segment's length, so short bangs do not flutter as
        // much as long strands. Explicit clothing response has a smaller budget;
        // unclassified accessories retain inertia only, without updraft.
        [Range(0,MaxHairAngle)] public float ambientHairAngle=2.2f;
        [Range(0,MaxClothAngle)] public float ambientClothAngle;
        public float HairTravel {get;private set;}
        public float ClothTravel {get;private set;}
        public int WindStrands {get;private set;}
        const float Spring=140,Damping=19;
        bool reset=true,applied;
        double airClock;
        float airFade;
        public void ResetSimulation() { Restore(); reset=true;airFade=0; }
        public void RestorePose(){Restore();}
        void OnEnable() { reset=true;airFade=0; }
        void OnDisable() { Restore();reset=true; }
        void OnApplicationPause(bool paused) { ResetSimulation(); }
        void Update() { Restore(); }
        void Restore()
        {
            if(!applied)return;
            foreach(var strand in strands)
            {
                if(strand.bone && strand.poseCaptured)strand.bone.localRotation=strand.animatedRotation;
                strand.poseCaptured=false;
            }
            applied=false;
        }
        void LateUpdate() { Step(Time.deltaTime); }
        public void Step(float dt)
        {
            if(dt<=0)return;
            if(dt>.10f) { reset=true;airFade=0; }
            // Also support deterministic manual stepping in editor reviews.
            // Update normally restores before Animator writes the new pose.
            Restore();
            dt=Mathf.Min(dt,1f/30);int steps=Mathf.Max(1,Mathf.CeilToInt(dt*120));float h=dt/steps;
            airClock+=dt;airFade=Mathf.Min(1,airFade+dt/1.4f);
            float fade=airFade*airFade*airFade*(airFade*(airFade*6-15)+10);
            // A coherent horizontal breeze with unequal, slow periods avoids
            // synchronized pendulums and random high-frequency jitter. Air never
            // supplies a vertical force or stretches a strand's authored length.
            Vector3 flow=new Vector3(.72f*(float)Math.Sin(airClock*.72)+.28f*(float)Math.Sin(airClock*1.17+.65),0,
                .32f*(float)Math.Sin(airClock*.47+1.2))*fade;
            WindStrands=0;
            // Ordered root-to-tip chains; target includes the parent's solved pose.
            foreach(var strand in strands)
            {
                if(!strand.enabled || !strand.bone || !strand.tip)continue;
                strand.animatedRotation=strand.bone.localRotation;
                strand.poseCaptured=true;
                if(!strand.airClassified)ClassifyAirResponse(strand);
                Vector3 origin=strand.bone.position,target=strand.tip.position,axis=target-origin;
                float length=axis.magnitude;if(length<.0001f)continue;
                if(reset || Vector3.Distance(strand.point,target)>.3f) { strand.point=target;strand.velocity=Vector3.zero; }
                Vector3 force=Vector3.zero;
                bool cloth=strand.wind=="cloth";
                bool hair=strand.wind=="hair" || (string.IsNullOrEmpty(strand.wind) && strand.isHair);
                float airAngle=(cloth?Mathf.Clamp(ambientClothAngle,0,MaxClothAngle):hair?Mathf.Clamp(ambientHairAngle,0,MaxHairAngle):0)*Mathf.Deg2Rad;
                if(airAngle>0)
                {
                    WindStrands++;
                    float response=string.IsNullOrEmpty(strand.wind)?strand.airResponse:Mathf.Clamp01(strand.windResponse);
                    force=Vector3.ProjectOnPlane(flow,axis/length)*(length*Mathf.Tan(airAngle)*response*Spring);
                }
                var previousPoint=strand.point;
                for(int i=0;i<steps;i++)
                {
                    strand.velocity+=((target-strand.point)*Spring+force)*h;
                    strand.velocity*=Mathf.Exp(-Damping*h);strand.point+=strand.velocity*h;
                }
                Vector3 predicted=strand.point;
                for(int iteration=0;iteration<3;iteration++)
                {
                    strand.point=origin+LimitDirection(axis,strand.point-origin,length,strand.angle);
                    foreach(var sphere in colliders)
                    {
                        if(!sphere.enabled || !sphere.bone || !Applies(strand,sphere.id))continue;
                        Vector3 center=sphere.bone.TransformPoint(sphere.offset),delta=strand.point-center;
                        var scale=sphere.bone.lossyScale;
                        float colliderScale=sphere.localRadius?Mathf.Max(Mathf.Abs(scale.x),Mathf.Abs(scale.y),Mathf.Abs(scale.z)):Mathf.Abs(transform.lossyScale.x);
                        float radius=sphere.radius*colliderScale+strand.radius*Mathf.Abs(transform.lossyScale.x);
                        if(delta.sqrMagnitude<radius*radius)
                            strand.point=center+(delta.sqrMagnitude>.000001f?delta.normalized:(target-center).normalized)*radius;
                    }
                    foreach(var plane in planes)
                    {
                        if(!plane.enabled || !plane.bone || !Applies(strand,plane.id))continue;
                        Vector3 normal=plane.bone.TransformDirection(plane.normal).normalized;
                        float distance=Vector3.Dot(strand.point-plane.bone.TransformPoint(plane.offset),normal);
                        float radius=strand.radius*Mathf.Abs(transform.lossyScale.x);
                        if(distance<radius)strand.point+=normal*(radius-distance);
                    }
                }
                // Anatomical silhouette limit wins over an unsatisfiable collider;
                // do not turn hair inside out trying to solve intersecting spheres.
                Vector3 limited=LimitDirection(axis,strand.point-origin,length,strand.angle);
                // FromToRotation loses very small per-frame angles to dot-product
                // rounding on short hair segments (especially at 120 Hz). atan2
                // retains the cross-product signal instead of freezing the tip.
                Vector3 from=axis/length,to=limited/length,cross=Vector3.Cross(from,to);
                float sine=cross.magnitude;
                var rotation=sine>1e-8f?Quaternion.AngleAxis(Mathf.Atan2(sine,Vector3.Dot(from,to))*Mathf.Rad2Deg,cross/sine):Quaternion.identity;
                strand.bone.rotation=rotation*strand.bone.rotation;
                strand.point=strand.tip.position;
                if(hair)HairTravel+=Vector3.Distance(previousPoint,strand.point);
                if(cloth)ClothTravel+=Vector3.Distance(previousPoint,strand.point);
                // Constraints should not accumulate a velocity pushing forever
                // into a head/body collider or the angular boundary. Remove only
                // the component opposed to the actual correction; tangential
                // motion remains free and naturally damped by the spring.
                Vector3 correction=strand.point-predicted;
                if(correction.sqrMagnitude>.00000001f)
                {
                    Vector3 normal=correction.normalized;
                    strand.velocity-=normal*Mathf.Min(0,Vector3.Dot(strand.velocity,normal));
                }
            }
            reset=false;applied=true;
        }
        static Vector3 LimitDirection(Vector3 axis,Vector3 candidate,float length,float limit)
        {
            if(candidate.sqrMagnitude<1e-12f)return axis;
            var from=axis/length;var to=candidate.normalized;var cross=Vector3.Cross(from,to);
            float sine=cross.magnitude,dot=Vector3.Dot(from,to),angle=Mathf.Atan2(sine,dot)*Mathf.Rad2Deg;
            // Returning the candidate directly inside the cone avoids the tiny
            // displacement dead zone of Vector3.RotateTowards on short strands.
            if(angle<=limit)return to*length;
            var normal=sine>1e-8f?cross/sine:Vector3.Cross(from,Mathf.Abs(from.y)<.9f?Vector3.up:Vector3.right).normalized;
            return Quaternion.AngleAxis(limit,normal)*from*length;
        }
        void ClassifyAirResponse(Strand strand)
        {
            strand.airClassified=true;
            int hairDepth=0;
            for(var bone=strand.bone;bone && bone!=transform;bone=bone.parent)
            {
                string name=bone.name;
                // Explicitly keep garments and accessories free of ambient air.
                if(name.IndexOf("skirt",StringComparison.OrdinalIgnoreCase)>=0 ||
                   name.IndexOf("sleeve",StringComparison.OrdinalIgnoreCase)>=0 ||
                   name.IndexOf("cloth",StringComparison.OrdinalIgnoreCase)>=0 ||
                   name.IndexOf("ribbon",StringComparison.OrdinalIgnoreCase)>=0)
                { strand.isHair=false;return; }
                if(name.IndexOf("hair",StringComparison.OrdinalIgnoreCase)>=0 ||
                   name.IndexOf("髪",StringComparison.Ordinal)>=0 ||
                   name.IndexOf("アホ毛",StringComparison.Ordinal)>=0)hairDepth++;
            }
            strand.isHair=hairDepth>0;
            // Root attachment remains quiet; the moving parent plus slightly
            // softer distal response forms a travelling bend towards the tips.
            strand.airResponse=Mathf.Min(1,.48f+hairDepth*.13f);
        }
    }
}
