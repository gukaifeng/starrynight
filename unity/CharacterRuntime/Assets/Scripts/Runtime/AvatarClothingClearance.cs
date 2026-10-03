using System;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class AvatarClothingClearanceState
    {
        public string origin="starrynight.host-clothing-clearance.v1";
        public int capsules,meshCalibrated,clothSegments,armCorrections,clothContacts;
        public float armWeight=1,maximumAddedPenetration,maximumClothPenetration,maximumCorrection;
    }

    // Bounded collision proxies, not a replacement mesh/Cloth simulation. Sizes
    // come from the actual skinned outfit once on bind. All per-frame work is on
    // a few capsules and authored bone chains; no mesh baking in the frame loop.
    [DefaultExecutionOrder(100)]
    public sealed class AvatarClothingClearance:MonoBehaviour
    {
        public sealed class Capsule
        {
            public Transform a,b,root;public string human;public float radius,scale=1;
            public Vector3 A=>a.position;public Vector3 B=>b.position;
            public float Radius=>radius*Mathf.Abs(root.lossyScale.x)/scale;
        }
        sealed class Arm
        {
            public Transform[] bones;public Quaternion[] baseline,proposed,raw;
            public Capsule[] shape;public float clearance,weight=1;
        }
        public AvatarClothingClearanceState State {get;private set;}=new AvatarClothingClearanceState();
        public Capsule[] Capsules {get;private set;}=Array.Empty<Capsule>();
        readonly Dictionary<string,Transform> human=new Dictionary<string,Transform>();
        readonly Dictionary<AvatarSecondaryMotion.Strand,Capsule[]> clothCapsules=new Dictionary<AvatarSecondaryMotion.Strand,Capsule[]>();
        Arm[] arms=Array.Empty<Arm>();Capsule torso;ViewerCharacter actor;
        AvatarSecondaryMotion secondary;
        float height=1;bool captured,applied;
        public void Initialize(ViewerCharacter character,HostEmotionRig rig)
        {
            if(actor)return;actor=character;
            foreach(var j in rig.joints)if(j.bone)human[j.human]=j.bone;
            foreach(var j in rig.naturalJoints??Array.Empty<HostEmotionRig.Joint>())if(j.bone)human[j.human]=j.bone;
            if(!human.ContainsKey("Hips") && rig.leftFoot?.parent?.parent?.parent==rig.rightFoot?.parent?.parent?.parent && rig.leftFoot)
                human["Hips"]=rig.leftFoot.parent.parent.parent;
            height=Mathf.Max(.2f,character.RestBounds().size.y*character.transform.lossyScale.y);
            var list=new List<Capsule>();
            Capsule Add(string name,string start,string end,float fallback) {
                if(!human.TryGetValue(start,out var a) || !human.TryGetValue(end,out var b))return null;
                var c=new Capsule {human=name,a=a,b=b,root=character.transform,scale=Mathf.Max(.00001f,Mathf.Abs(character.transform.lossyScale.x)),radius=height*fallback};list.Add(c);return c;
            }
            torso=Add("Torso","Hips","Chest",.075f);
            var armList=new List<Arm>();
            foreach(string side in new[]{"Left","Right"}) {
                var upper=Add(side+"UpperArm",side+"UpperArm",side+"LowerArm",.024f);
                var lower=Add(side+"LowerArm",side+"LowerArm",side+"Hand",.021f);
                if(upper!=null && lower!=null && human.TryGetValue(side+"Shoulder",out var shoulder))armList.Add(new Arm {bones=new[]{shoulder,upper.a,lower.a,lower.b},shape=new[]{upper,lower},
                    baseline=new Quaternion[4],proposed=new Quaternion[4],raw=new Quaternion[4]});
                Add(side+"Thigh",side+"UpperLeg",side+"LowerLeg",.036f);
            }
            Capsules=list.ToArray();arms=armList.ToArray();State.capsules=Capsules.Length;
            CalibrateEnvelope();
            secondary=character.GetComponent<AvatarSecondaryMotion>();
            if(secondary) {
                secondary.clothingClearance=this;
                foreach(var strand in secondary.strands)if(strand.bone) {
                    var eligible=new List<Capsule>();
                    foreach(var cap in Capsules)if(cap.human=="Torso" || !(strand.bone.IsChildOf(cap.a) || strand.bone.IsChildOf(cap.b)))eligible.Add(cap);
                    clothCapsules[strand]=eligible.ToArray();
                }
            }
            var restore=gameObject.AddComponent<AvatarClothingClearanceRestore>();restore.driver=this;
        }
        void CalibrateEnvelope()
        {
            var samples=new List<float>[Capsules.Length];
            var starts=new Vector3[Capsules.Length];var axes=new Vector3[Capsules.Length];var lengths=new float[Capsules.Length];
            for(int i=0;i<samples.Length;i++)samples[i]=new List<float>();
            for(int i=0;i<Capsules.Length;i++){starts[i]=Capsules[i].A;axes[i]=Capsules[i].B-starts[i];lengths[i]=Mathf.Max(1e-8f,axes[i].sqrMagnitude);}
            foreach(var skin in actor.GetComponentsInChildren<SkinnedMeshRenderer>(true)) {
                if(!skin.sharedMesh || !skin.sharedMesh.isReadable)continue;
                Mesh baked=null;
                try {
                    var weights=skin.sharedMesh.boneWeights;
                    if(weights.Length==0)continue;
                    var bones=skin.bones;var masks=new int[bones.Length];
                    for(int k=0;k<Capsules.Length;k++) {
                        for(int b=0;b<bones.Length;b++)if(bones[b]==Capsules[k].a || bones[b]==Capsules[k].b ||
                            (Capsules[k]==torso && (bones[b]==human.GetValueOrDefault("Spine"))))masks[b]|=1<<k;
                    }
                    baked=new Mesh();skin.BakeMesh(baked,false);var vertices=baked.vertices;
                    // Bound calibration work independently of imported polygon count.
                    int stride=Mathf.Max(1,vertices.Length/16000);
                    for(int v=0;v<vertices.Length && v<weights.Length;v+=stride) {
                        var w=weights[v];var point=skin.transform.TransformPoint(vertices[v]);
                        for(int k=0;k<Capsules.Length;k++) {
                            int bit=1<<k;
                            float influence=((masks[w.boneIndex0]&bit)!=0?w.weight0:0)+((masks[w.boneIndex1]&bit)!=0?w.weight1:0)+
                                ((masks[w.boneIndex2]&bit)!=0?w.weight2:0)+((masks[w.boneIndex3]&bit)!=0?w.weight3:0);
                            if(influence<.45f)continue;
                            float t=Vector3.Dot(point-starts[k],axes[k])/lengths[k];
                            // Don't mistake shoulders, skirts or hand accessories for sleeve width.
                            if(t<.12f || t>.88f)continue;
                            float distance=Vector3.Distance(point,starts[k]+axes[k]*t);
                            if(distance>height*.006f && distance<height*.18f)samples[k].Add(distance);
                        }
                    }
                } catch(InvalidOperationException) {
                    // Old non-readable bundles still get anatomical proxy bounds.
                } finally {if(baked){if(Application.isPlaying)Destroy(baked);else DestroyImmediate(baked);}}
            }
            for(int k=0;k<Capsules.Length;k++)if(samples[k].Count>=12) {
                samples[k].Sort();
                float measured=samples[k][Mathf.FloorToInt((samples[k].Count-1)*.90f)];
                float maximum=height*(Capsules[k]==torso?.14f:Capsules[k].human.EndsWith("Thigh")?.065f:.065f);
                Capsules[k].radius=Mathf.Clamp(measured+height*.0015f,height*.012f,maximum);State.meshCalibrated++;
            }
        }
        public void CaptureBaseline()
        {
            Restore();captured=true;
            foreach(var arm in arms) {
                for(int i=0;i<arm.bones.Length;i++)arm.baseline[i]=arm.bones[i].localRotation;
                arm.clearance=Clearance(arm);
            }
        }
        float Clearance(Arm arm)
        {
            if(torso==null)return 0;
            float value=float.PositiveInfinity;
            foreach(var cap in arm.shape) {
                // Shoulder attachment necessarily overlaps the torso. Test the
                // free part, not the sewing seam/upper-arm root.
                var start=Vector3.Lerp(cap.A,cap.B,cap==arm.shape[0]?.28f:0);
                ClosestSegments(start,cap.B,torso.A,torso.B,out var p,out var q,out _);
                value=Mathf.Min(value,Vector3.Distance(p,q)-cap.Radius-torso.Radius);
            }
            return value;
        }
        void Blend(Arm arm,float fraction) {for(int i=0;i<arm.bones.Length;i++)arm.bones[i].localRotation=Quaternion.Slerp(arm.baseline[i],arm.proposed[i],fraction);}
        void LateUpdate(){Step(Time.unscaledDeltaTime);}
        public void Step(float dt)
        {
            if(!captured || !actor || !actor.gameObject.activeInHierarchy || dt<=0)return;
            Restore();State.armWeight=1;
            foreach(var arm in arms) {
                for(int i=0;i<arm.bones.Length;i++)arm.raw[i]=arm.proposed[i]=arm.bones[i].localRotation;
                Blend(arm,0);
                float threshold=Mathf.Min(arm.clearance,Clearance(arm))-height*.0004f;
                Blend(arm,1);
                float allowed=1;
                if(Clearance(arm)<threshold) {
                    // Solve from the author's pose, not from last frame's solved
                    // pose. Eight fixed iterations, no additive accumulation.
                    float low=0,high=1;
                    for(int iteration=0;iteration<8;iteration++) {
                        float mid=(low+high)*.5f;Blend(arm,mid);
                        if(Clearance(arm)>=threshold)low=mid;else high=mid;
                    }
                    allowed=low;State.armCorrections++;
                }
                arm.weight=Mathf.Min(allowed,Mathf.Lerp(arm.weight,allowed,1-Mathf.Exp(-Mathf.Min(dt,.05f)/.22f)));
                Blend(arm,arm.weight);
                State.armWeight=Mathf.Min(State.armWeight,arm.weight);
                State.maximumAddedPenetration=Mathf.Max(State.maximumAddedPenetration,threshold+height*.0004f-Clearance(arm));
                for(int i=0;i<arm.bones.Length;i++)State.maximumCorrection=Mathf.Max(State.maximumCorrection,Quaternion.Angle(arm.raw[i],arm.bones[i].localRotation));
            }
            applied=true;
        }
        public void Restore()
        {
            if(!applied)return;
            foreach(var arm in arms)for(int i=0;i<arm.bones.Length;i++)if(arm.bones[i])arm.bones[i].localRotation=arm.raw[i];
            applied=false;
        }
        public void Release(){Restore();captured=false;foreach(var arm in arms)arm.weight=1;}
        void OnDisable(){Release();}
        public void ProjectCloth(AvatarSecondaryMotion.Strand strand,Vector3 origin,Vector3 authored,ref Vector3 point,float radius)
        {
            if(!clothCapsules.TryGetValue(strand,out var eligible))return;
            foreach(var cap in eligible) {
                // Do not collide a sleeve with the arm it is attached to, or a
                // skirt root with its own thigh. Other limbs remain obstacles.
                float r=cap.Radius+radius;
                ClosestSegments(origin,authored,cap.A,cap.B,out var baseline,out var b,out _);
                float permitted=Mathf.Min(r,Vector3.Distance(baseline,b));
                if(ProjectSegment(origin,ref point,cap.A,cap.B,Mathf.Max(0,permitted-height*.0002f)))State.clothContacts++;
            }
        }
        public void MeasureCloth(AvatarSecondaryMotion.Strand strand,Vector3 origin,Vector3 authored,Vector3 point)
        {
            if(!clothCapsules.TryGetValue(strand,out var eligible))return;
            foreach(var cap in eligible) {
                ClosestSegments(origin,authored,cap.A,cap.B,out var p,out var q,out _);
                float baseline=Vector3.Distance(p,q);
                ClosestSegments(origin,point,cap.A,cap.B,out p,out q,out _);
                // New penetrations only. A rest-pose sewing seam/intentional
                // overlap does not become a force trying to explode the outfit.
                State.maximumClothPenetration=Mathf.Max(State.maximumClothPenetration,Mathf.Min(cap.Radius+strand.radius*Mathf.Abs(actor.transform.lossyScale.x),baseline)-Vector3.Distance(p,q));
            }
        }
        // Capsule vs the whole bone segment. Tip-only tests miss an arm passing
        // through the middle of a long sleeve/skirt segment.
        public static bool ProjectSegment(Vector3 origin,ref Vector3 tip,Vector3 a,Vector3 b,float radius)
        {
            ClosestSegments(origin,tip,a,b,out var p,out var q,out float t);
            var delta=p-q;float distance=delta.magnitude;
            if(distance>=radius || t<1e-5f || radius<=0)return false;
            var normal=distance>1e-7f?delta/distance:Vector3.Cross(tip-origin,b-a).normalized;
            if(normal.sqrMagnitude<.5f)normal=Vector3.Cross(tip-origin,Mathf.Abs((tip-origin).normalized.y)<.9f?Vector3.up:Vector3.right).normalized;
            tip+=normal*Mathf.Min((radius-distance)/Mathf.Max(.25f,t),(tip-origin).magnitude*.18f);return true;
        }
        // Ericson's clamped closest-points formulation; also handles two spheres
        // (zero-length segments) and parallel/nearly parallel bones.
        public static void ClosestSegments(Vector3 a,Vector3 b,Vector3 c,Vector3 d,out Vector3 p,out Vector3 q,out float s)
        {
            var u=b-a;var v=d-c;var r=a-c;float aa=Vector3.Dot(u,u),ee=Vector3.Dot(v,v),f=Vector3.Dot(v,r),t;
            if(aa<1e-12f && ee<1e-12f){s=t=0;}
            else if(aa<1e-12f){s=0;t=Mathf.Clamp01(f/ee);}
            else {
                float cc=Vector3.Dot(u,r);
                if(ee<1e-12f){t=0;s=Mathf.Clamp01(-cc/aa);}
                else {
                    float bb=Vector3.Dot(u,v),denom=aa*ee-bb*bb;
                    s=denom>1e-12f?Mathf.Clamp01((bb*f-cc*ee)/denom):0;t=(bb*s+f)/ee;
                    if(t<0){t=0;s=Mathf.Clamp01(-cc/aa);}else if(t>1){t=1;s=Mathf.Clamp01((bb-cc)/aa);}
                }
            }
            p=a+u*s;q=c+v*t;
        }
    }
}
