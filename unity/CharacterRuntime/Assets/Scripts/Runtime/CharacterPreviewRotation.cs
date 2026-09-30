using UnityEngine;

namespace ModelSpace
{
    // Transient offsets only: never part of CharacterViewPose or its saved target.
    public sealed class CharacterPreviewRotation
    {
        public const float MaximumYaw=18,MaximumPitch=8;
        public const float ShakeTravel=1.5f,ShakeWindow=5,ShakeCooldown=20;
        Vector2 offset,target,velocity,origin;
        bool returning;
        float clock,windowStart,travel,lastReaction=-100,lastMove=-100;
        int reversals;
        Vector2 previousTarget,lastDirection;
        public int ShakeCount {get;private set;}
        public float ShakeIntensity {get;private set;}
        public bool Active {get;private set;}
        public Vector2 Offset => offset;
        public float PeakYaw {get;private set;}
        public float PeakPitch {get;private set;}
        public int Count {get;private set;}
        public int ReturnCount {get;private set;}
        public void Begin() {
            if(clock-lastMove>.8f || clock-windowStart>ShakeWindow) {windowStart=clock;travel=0;reversals=0;lastDirection=Vector2.zero;}
            Active=true;returning=false;origin=offset;target=offset;previousTarget=offset;Count++;
        }
        public void Move(float horizontal,float vertical)
        {
            if(!Active || !float.IsFinite(horizontal) || !float.IsFinite(vertical))return;
            target=new Vector2(Mathf.Clamp(origin.x-horizontal*90,-MaximumYaw,MaximumYaw),
                Mathf.Clamp(origin.y-vertical*45,-MaximumPitch,MaximumPitch));
            if(clock-windowStart>ShakeWindow) {windowStart=clock;travel=0;reversals=0;lastDirection=Vector2.zero;}
            var delta=new Vector2((target.x-previousTarget.x)/MaximumYaw,(target.y-previousTarget.y)/MaximumPitch);
            if(delta.magnitude>.10f) {
                if(lastDirection.sqrMagnitude>0 && Vector2.Dot(lastDirection,delta.normalized)<-.35f)reversals++;
                travel+=delta.magnitude;lastDirection=delta.normalized;previousTarget=target;lastMove=clock;
            }
        }
        public bool End(bool react=false)
        {
            if(!Active)return false;
            Active=false;returning=true;target=Vector2.zero;
            if(react && TryReact())return true;
            if(!react) {travel=0;reversals=0;lastDirection=Vector2.zero;}
            return false;
        }
        bool TryReact()
        {
            if(clock-lastReaction>=ShakeCooldown && clock-windowStart>=.35f && clock-windowStart<=ShakeWindow && travel>=ShakeTravel && reversals>=2) {
                ShakeCount++;ShakeIntensity=Mathf.Clamp01(.5f+travel/20);lastReaction=clock;
                travel=0;reversals=0;lastDirection=Vector2.zero;return true;
            }
            return false;
        }
        public void Step(float deltaTime)
        {
            if(!float.IsFinite(deltaTime) || deltaTime<=0)return;
            clock+=deltaTime;
            if(Active)TryReact(); // Threshold is observed while the finger is still down.
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
            clock=windowStart=travel=0;reversals=ShakeCount=0;ShakeIntensity=0;lastReaction=lastMove=-100;previousTarget=lastDirection=Vector2.zero;
        }
    }
}
