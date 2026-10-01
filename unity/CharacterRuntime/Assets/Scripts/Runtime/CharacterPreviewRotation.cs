using UnityEngine;

namespace ModelSpace
{
    // Transient offsets only: never part of CharacterViewPose or its saved target.
    public sealed class CharacterPreviewRotation
    {
        public const float MaximumYaw=180,MaximumPitch=14,MaximumAngularSpeed=300;
        public const float MinimumRatio=.95f,MaximumRatio=1.05f,PinchThreshold=.025f;
        public const float ShakeTravel=1.5f,ShakeWindow=5,ShakeCooldown=20;
        Vector2 offset,target,velocity,origin;
        bool returning;
        float clock,windowStart,travel,lastReaction=-100,lastMove=-100;
        int reversals;
        Vector2 previousTarget,lastDirection;
        float scale=1,scaleTarget=1,scaleOrigin=1,scaleVelocity,pinchStart;
        bool scaleReturning;
        public bool Pinching {get;private set;}
        public float ScaleRatio => scale;
        public float MinimumObservedRatio {get;private set;}=1;
        public float MaximumObservedRatio {get;private set;}=1;
        public int PinchCount {get;private set;}
        public int PinchReturnCount {get;private set;}
        public int PinchReactionCount {get;private set;}
        public int ReactionCount {get;private set;}
        public string ReactionKind {get;private set;}="shake";
        public float ReactionIntensity {get;private set;}
        public int ShakeCount {get;private set;}
        public float ShakeIntensity {get;private set;}
        public bool Active {get;private set;}
        public Vector2 Offset => offset;
        public float PeakYaw {get;private set;}
        public float PeakPitch {get;private set;}
        public int Count {get;private set;}
        public int ReturnCount {get;private set;}
        public void Begin() {
            EndPinch();
            if(clock-lastMove>.8f || clock-windowStart>ShakeWindow) {windowStart=clock;travel=0;reversals=0;lastDirection=Vector2.zero;}
            Active=true;returning=false;origin=target=offset;velocity=previousTarget=Vector2.zero;Count++;
        }
        public void BeginPinch() {
            End();Pinching=true;scaleReturning=false;scaleOrigin=scale;scaleTarget=scale;pinchStart=clock;PinchCount++;
        }
        public void Pinch(float ratio) {
            if(!Pinching || !float.IsFinite(ratio) || ratio<=0)return;
            scaleTarget=Mathf.Clamp(scaleOrigin*ratio,MinimumRatio,MaximumRatio);
        }
        public bool EndPinch(bool react=false) {
            if(!Pinching)return false;
            bool reacted=react && TryReactToPinch();
            Pinching=false;scaleReturning=true;scaleTarget=1;return reacted;
        }
        bool TryReactToPinch() {
            float delta=scaleTarget-scaleOrigin;
            if(clock-lastReaction<ShakeCooldown || clock-pinchStart<.22f || Mathf.Abs(delta)<PinchThreshold)return false;
            PinchReactionCount++;ReactionCount++;ReactionKind=delta>0 ? "pinch_out" : "pinch_in";
            ReactionIntensity=Mathf.Clamp01(.5f+Mathf.Abs(delta)*6);lastReaction=clock;return true;
        }
        public void Move(float horizontal,float vertical,float horizontalSpeed=0,float edgeRatio=float.NaN)
        {
            if(!Active || !float.IsFinite(horizontal) || !float.IsFinite(vertical) || !float.IsFinite(horizontalSpeed))return;
            var input=new Vector2(horizontal,vertical);
            // The host maps travel from the initial touch to the nearby edge.
            // At either edge the actor faces away, independent of finger speed
            // or off-centre starting point. Older hosts use a half-screen span.
            float ratio=Mathf.Clamp(float.IsFinite(edgeRatio) ? edgeRatio : horizontal*2,-1,1);
            target=new Vector2(Mathf.Lerp(origin.x,ratio>=0 ? -MaximumYaw : MaximumYaw,Mathf.Abs(ratio)),
                Mathf.Clamp(origin.y-vertical*65,-MaximumPitch,MaximumPitch));
            if(clock-windowStart>ShakeWindow) {windowStart=clock;travel=0;reversals=0;lastDirection=Vector2.zero;}
            // Reactions still measure actual screen travel, independently of
            // off-centre edge mapping. One-way viewing is not repeated shaking.
            var delta=new Vector2((input.x-previousTarget.x)*5,(input.y-previousTarget.y)*5.625f);
            if(delta.magnitude>.10f) {
                if(lastDirection.sqrMagnitude>0 && Vector2.Dot(lastDirection,delta.normalized)<-.35f)reversals++;
                travel+=delta.magnitude;lastDirection=delta.normalized;previousTarget=input;lastMove=clock;
            }
        }
        public bool End(bool react=false)
        {
            if(!Active)return false;
            Active=false;returning=true;target=Vector2.zero;
            // Equivalent orientation, shortest return to the saved front view.
            offset.x=Mathf.DeltaAngle(0,offset.x);velocity=Vector2.zero;
            if(react && TryReact())return true;
            if(!react) {travel=0;reversals=0;lastDirection=Vector2.zero;}
            return false;
        }
        bool TryReact()
        {
            if(clock-lastReaction>=ShakeCooldown && clock-windowStart>=.35f && clock-windowStart<=ShakeWindow && travel>=ShakeTravel && reversals>=2) {
                ShakeCount++;ShakeIntensity=Mathf.Clamp01(.5f+travel/20);lastReaction=clock;
                ReactionCount++;ReactionKind="shake";ReactionIntensity=ShakeIntensity;
                travel=0;reversals=0;lastDirection=Vector2.zero;return true;
            }
            return false;
        }
        public void Step(float deltaTime)
        {
            if(!float.IsFinite(deltaTime) || deltaTime<=0)return;
            clock+=deltaTime;
            if(Active)TryReact(); // Threshold is observed while the finger is still down.
            if(Pinching)TryReactToPinch();
            scale=Mathf.SmoothDamp(scale,scaleTarget,ref scaleVelocity,Pinching ? .08f : .22f,Mathf.Infinity,Mathf.Min(deltaTime,.05f));
            scale=Mathf.Clamp(scale,MinimumRatio,MaximumRatio);
            MinimumObservedRatio=Mathf.Min(MinimumObservedRatio,scale);MaximumObservedRatio=Mathf.Max(MaximumObservedRatio,scale);
            if(scaleReturning && Mathf.Abs(scale-1)<.00005f && Mathf.Abs(scaleVelocity)<.0001f) {
                scale=scaleTarget=1;scaleVelocity=0;scaleReturning=false;PinchReturnCount++;
            }
            // Speed-limited SmoothDamp otherwise varies with refresh rate while
            // saturated. Small fixed upper steps keep 30/60/120 Hz consistent.
            float remaining=Mathf.Min(deltaTime,.05f);
            while(remaining>.000001f) {
                float step=Mathf.Min(remaining,1f/120);
                offset=Vector2.SmoothDamp(offset,target,ref velocity,Active ? .10f : .28f,MaximumAngularSpeed,step);
                remaining-=step;
            }
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
            Pinching=scaleReturning=false;scale=scaleTarget=scaleOrigin=1;scaleVelocity=pinchStart=0;
            MinimumObservedRatio=MaximumObservedRatio=1;
            PinchCount=PinchReturnCount=PinchReactionCount=ReactionCount=0;ReactionKind="shake";ReactionIntensity=0;
        }
    }
}
