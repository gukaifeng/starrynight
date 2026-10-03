using System;
using UnityEngine;

namespace ModelSpace
{
    // Host presentation adaptation, NOT an authored PhysBone or ragdoll. The
    // original arm pose stays authoritative; only small rotational inertia is
    // added when the user/ambient presentation rotates the whole character.
    [DefaultExecutionOrder(95)]
    public sealed class AvatarArmFollow : MonoBehaviour
    {
        [Serializable] public sealed class Joint {
            public Transform bone;public float limit=3;
            [NonSerialized] public Quaternion raw;
        }
        public Joint[] joints=Array.Empty<Joint>();
        Quaternion previousRoot;
        Vector3 offset,velocity;
        bool initialized,applied;
        public float MaximumOffset {get;private set;}
        public void Restore()
        {
            if(!applied)return;
            foreach(var joint in joints)if(joint.bone)joint.bone.localRotation=joint.raw;
            applied=false;
        }
        public void Reset(){Restore();offset=velocity=Vector3.zero;previousRoot=transform.rotation;initialized=true;MaximumOffset=0;}
        void OnEnable(){Reset();}
        void OnDisable(){Restore();initialized=false;}
        void Awake(){var restore=GetComponent<AvatarArmFollowRestore>() ?? gameObject.AddComponent<AvatarArmFollowRestore>();restore.driver=this;}
        void LateUpdate(){Step(Time.unscaledDeltaTime);}
        public void Step(float dt)
        {
            if(!initialized || dt>.1f){Reset();return;}
            if(dt<=0)return;
            var delta=transform.rotation*Quaternion.Inverse(previousRoot);previousRoot=transform.rotation;
            if(delta.w<0)delta=new Quaternion(-delta.x,-delta.y,-delta.z,-delta.w);
            delta.ToAngleAxis(out float angle,out var axis);
            if(angle>180)angle-=360;
            var angularVelocity=float.IsFinite(axis.sqrMagnitude)?transform.InverseTransformDirection(axis)*Mathf.Clamp(angle/dt,-720,720):Vector3.zero;
            var target=Vector3.ClampMagnitude(-angularVelocity*.014f,4);
            int steps=Mathf.Max(1,Mathf.CeilToInt(dt*120));float h=dt/steps;
            for(int i=0;i<steps;i++){velocity+=(target-offset)*110*h;velocity*=Mathf.Exp(-18*h);offset+=velocity*h;offset=Vector3.ClampMagnitude(offset,4);}
            MaximumOffset=0;
            foreach(var joint in joints)if(joint.bone) {
                joint.raw=joint.bone.localRotation;
                var localOffset=Vector3.ClampMagnitude(offset*(joint.limit/4),joint.limit);
                float magnitude=localOffset.magnitude;MaximumOffset=Mathf.Max(MaximumOffset,magnitude);
                if(magnitude>1e-6f)joint.bone.rotation=Quaternion.AngleAxis(magnitude,transform.TransformDirection(localOffset/magnitude))*joint.bone.rotation;
            }
            applied=true;
        }
    }
}
