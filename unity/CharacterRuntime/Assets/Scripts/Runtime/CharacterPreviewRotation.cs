using UnityEngine;

namespace ModelSpace
{
    // Transient offsets only: never part of CharacterViewPose or its saved target.
    public sealed class CharacterPreviewRotation
    {
        public const float MaximumYaw=18,MaximumPitch=8;
        Vector2 offset,target,velocity,origin;
        bool returning;
        public bool Active {get;private set;}
        public Vector2 Offset => offset;
        public float PeakYaw {get;private set;}
        public float PeakPitch {get;private set;}
        public int Count {get;private set;}
        public int ReturnCount {get;private set;}
        public void Begin() {Active=true;returning=false;origin=offset;target=offset;Count++;}
        public void Move(float horizontal,float vertical)
        {
            if(!Active || !float.IsFinite(horizontal) || !float.IsFinite(vertical))return;
            target=new Vector2(Mathf.Clamp(origin.x-horizontal*90,-MaximumYaw,MaximumYaw),
                Mathf.Clamp(origin.y-vertical*45,-MaximumPitch,MaximumPitch));
        }
        public void End()
        {
            if(!Active)return;
            Active=false;returning=true;target=Vector2.zero;
        }
        public void Step(float deltaTime)
        {
            if(!float.IsFinite(deltaTime) || deltaTime<=0)return;
            offset=Vector2.SmoothDamp(offset,target,ref velocity,Active ? .08f : .20f,Mathf.Infinity,Mathf.Min(deltaTime,.05f));
            // A quick reversal must not overshoot the hard gesture envelope.
            offset=new Vector2(Mathf.Clamp(offset.x,-MaximumYaw,MaximumYaw),Mathf.Clamp(offset.y,-MaximumPitch,MaximumPitch));
            PeakYaw=Mathf.Max(PeakYaw,Mathf.Abs(offset.x));PeakPitch=Mathf.Max(PeakPitch,Mathf.Abs(offset.y));
            if(returning && offset.sqrMagnitude<.000025f && velocity.sqrMagnitude<.0004f) {
                offset=velocity=target=Vector2.zero;returning=false;ReturnCount++;
            }
        }
        public void Reset()
        {
            Active=returning=false;offset=target=velocity=origin=Vector2.zero;
            PeakYaw=PeakPitch=0;Count=ReturnCount=0;
        }
    }
}
