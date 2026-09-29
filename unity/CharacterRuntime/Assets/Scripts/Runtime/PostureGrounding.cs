using System;
using UnityEngine;
namespace ModelSpace
{
    [Serializable] public sealed class GroundProbe
    {
        public Transform a,b,c,d;
        public Vector3 pa,pb,pc,pd;
        public Vector4 weights;
        public Vector3 World => (a?a.TransformPoint(pa)*weights.x:Vector3.zero)+(b?b.TransformPoint(pb)*weights.y:Vector3.zero)+(c?c.TransformPoint(pc)*weights.z:Vector3.zero)+(d?d.TransformPoint(pd)*weights.w:Vector3.zero);
    }
    // Compiled from the deformed contact extrema, at most 256 four-bone probes.
    // This prevents floor penetration; it is deliberately not furniture IK or self-collision.
    public sealed class PostureGrounding : MonoBehaviour
    {
        public Transform pivot;
        public GroundProbe[] probes=Array.Empty<GroundProbe>();
        Vector3 previous;bool applied;
        public float Lift { get; private set; }
        public void Restore(){if(applied && pivot)pivot.localPosition=previous;applied=false;}
        public void Apply()
        {
            if(!pivot || probes.Length==0)return;
            previous=pivot.localPosition;applied=true;
            float minimum=float.PositiveInfinity;
            foreach(var probe in probes)minimum=Mathf.Min(minimum,probe.World.y);
            // Tiny margin covers sampling/float noise. Required lift is continuous as bones move.
            Lift=Mathf.Max(0,.003f-minimum);
            pivot.position+=Vector3.up*Lift;
        }
        void OnDisable(){Restore();}
    }
}
