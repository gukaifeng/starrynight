using System;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public struct CharacterViewPose
    {
        public float yaw,pitch,scale,x,y;
        public static CharacterViewPose Default => new CharacterViewPose{scale=1};
        public bool IsDefault => Mathf.Abs(yaw)<.00001f && Mathf.Abs(pitch)<.00001f && Mathf.Abs(scale-1)<.00001f && Mathf.Abs(x)<.00001f && Mathf.Abs(y)<.00001f;
        public bool Valid => float.IsFinite(yaw)&&float.IsFinite(pitch)&&float.IsFinite(scale)&&float.IsFinite(x)&&float.IsFinite(y)&&scale>0;
    }
    // Author-owned transforms are unwound every frame. Native storage retains the
    // latest view per account/character; rotation never silently pans or zooms.
    public sealed class CharacterInspectionRotation
    {
        public const int Revision=6;
        public const float TurnFramingReserve=1.10f;
        public const float HoldSeconds=1, MaximumYaw=180, MaximumPitch=20;
        public const float MinimumScale=.78f,MaximumScale=1.28f,MaximumTranslation=.45f;
        Transform model;
        Camera camera;
        Bounds region;
        Vector3[] portraitPoints;
        Bounds portraitInput,portraitResult;
        bool portraitCached;
        Rect safe=new Rect(0,0,1,1),fitSafe;
        Bounds fitRegion;
        Matrix4x4 fitCamera;
        Vector2 fitAngles;
        Vector3 bodyPivotLocal,bodyPivot;
        bool rotationOnly;
        
        float fitFov,fitAspect,fitCeiling,projectionAspect;
        bool fitCached;
        Quaternion authoredRotation;
        Vector3 authoredPosition,authoredScale,pitchAxis=Vector3.right,screenUp=Vector3.up;
        Vector2 worldSpan=Vector2.one,translationVelocity;
        bool applied,returning,hasProjection;
        public bool FrameApplied => applied;
        float yawVelocity,pitchVelocity,scaleVelocity,chargeTime;
        CharacterViewPose requested=CharacterViewPose.Default,gestureStart=CharacterViewPose.Default,committed=CharacterViewPose.Default,chargeBase=CharacterViewPose.Default;
        public bool Preparing {get;private set;}
        public bool Active { get; private set; }
        public bool Moving {get;private set;}
        public float Yaw { get; private set; }
        public float TargetYaw { get; private set; }
        public float PeakYaw { get; private set; }
        public float LastReleasedYaw { get; private set; }
        public float Pitch { get; private set; }
        public float TargetPitch { get; private set; }
        public float PeakPitch { get; private set; }
        public float LastReleasedPitch { get; private set; }
        public float Scale {get;private set;}=1;
        public float TargetScale {get;private set;}=1;
        public Vector2 Translation {get;private set;}
        public Vector2 TargetTranslation {get;private set;}
        public int Count { get; private set; }
        public int RejectedCount { get; private set; }
        public int ReturnCount { get; private set; }
        public Rect ProjectedEnvelope {get;private set;}
        public CharacterViewPose Target => new CharacterViewPose{yaw=TargetYaw,pitch=TargetPitch,scale=TargetScale,x=TargetTranslation.x,y=TargetTranslation.y};
        public CharacterViewPose Current => new CharacterViewPose{yaw=Yaw,pitch=Pitch,scale=Scale,x=Translation.x,y=Translation.y};
        public void Bind(Transform target)
        {
            ResetImmediate();model=target;camera=null;hasProjection=false;fitCached=false;committed=CharacterViewPose.Default;
            PeakYaw=LastReleasedYaw=PeakPitch=LastReleasedPitch=0;Count=RejectedCount=ReturnCount=0;
            rotationOnly=false;bodyPivotLocal=Vector3.zero;portraitPoints=null;portraitCached=false;
            if(model) {
                var character=model.GetComponent<ViewerCharacter>();
                var neck=character ? CharacterContract.Resolve(model,character.Manifest.rig.neck) : null;
                var hips=neck;
                while(hips && hips!=model && !string.Equals(hips.name,"Hips",StringComparison.OrdinalIgnoreCase))hips=hips.parent;
                if(neck && hips && hips!=model)bodyPivotLocal=model.InverseTransformPoint((neck.position+hips.position)*.5f);
                bodyPivot=model.TransformPoint(bodyPivotLocal);
            }
        }
        public void Reject() { RejectedCount++; }
        public void Prepare()
        {
            if(!model || Active)return;
            Preparing=true;chargeTime=0;returning=false;chargeBase=requested;
        }
        public bool Begin() => Begin(Vector3.right);
        public bool Begin(Vector3 right)
        {
            if(!model || Active || !Finite(right))return false;
            var horizontal=Vector3.ProjectOnPlane(right,Vector3.up);
            if(horizontal.sqrMagnitude<.0001f)return false;
            pitchAxis=horizontal.normalized;
            if(Preparing)Assign(chargeBase);
            Active=true;Preparing=false;Moving=false;returning=false;Count++;return true;
        }
        public void BeginAdjustment(bool transforming=false) {
            if(!Active)return;
            Moving=true;rotationOnly=!transforming;
            gestureStart=Current;requested=gestureStart;ClearVelocity();
        }
        public void SetScreenSpace(Vector3 up,float width,float height)
        {
            if(Finite(up) && up.sqrMagnitude>.0001f && float.IsFinite(width) && float.IsFinite(height) && width>0 && height>0)
            {screenUp=up.normalized;worldSpan=new Vector2(width,height);}
        }
        Bounds PortraitEnvelope(Bounds input) {
            if(portraitCached && portraitInput==input)return portraitResult;
            if(portraitPoints==null && model) {
                var points=new List<Vector3>();var baked=new Mesh();
                foreach(var renderer in model.GetComponentsInChildren<Renderer>(false)) {
                    if(!renderer.enabled)continue;
                    Mesh mesh=null;
                    if(renderer is SkinnedMeshRenderer skin) {skin.BakeMesh(baked,false);mesh=baked;}
                    else if(renderer.TryGetComponent<MeshFilter>(out var filter))mesh=filter.sharedMesh;
                    if(!mesh)continue;
                    foreach(var point in mesh.vertices)points.Add(renderer.transform.TransformPoint(point));
                }
                portraitPoints=points.ToArray();
                if(Application.isPlaying)UnityEngine.Object.Destroy(baked);else UnityEngine.Object.DestroyImmediate(baked);
            }
            // Cropping only the full-body box's Y left the tail's depth at head
            // height. Use the actual neutral upper-body mesh to bound depth.
            float near=float.PositiveInfinity,far=float.NegativeInfinity;int count=0;
            foreach(var point in portraitPoints ?? Array.Empty<Vector3>()) {
                if(point.y<input.min.y || point.y>input.max.y || point.x<input.min.x || point.x>input.max.x)continue;
                near=Mathf.Min(near,point.z);far=Mathf.Max(far,point.z);count++;
            }
            var result=input;
            if(count>20 && far>near) {
                float margin=input.size.y*.04f;
                var min=input.min;var max=input.max;
                min.z=Mathf.Max(min.z,near-margin);max.z=Mathf.Min(max.z,far+margin);
                if(max.z>min.z)result.SetMinMax(min,max);
            }
            portraitCached=true;portraitInput=input;portraitResult=result;return result;
        }
        // Keep the existing close portrait size. Reserve a little headroom from
        // the first frame; opening the editor must not reframe the character.
        public void ConstrainComposition(Bounds portrait,Quaternion rotation,float aspect,float fov,Rect viewport,ref Vector3 focus,ref float distance) {
            var envelope=PortraitEnvelope(portrait);
            viewport.height-=Mathf.Min(.05f,viewport.height*.06f);
            float tan=Mathf.Tan(fov*Mathf.Deg2Rad*.5f);
            float left=(2*viewport.xMin-1)*tan*aspect,right=(2*viewport.xMax-1)*tan*aspect;
            float bottom=(2*viewport.yMin-1)*tan,top=(2*viewport.yMax-1)*tan;
            var inverse=Quaternion.Inverse(rotation);
            Vector2 low=Vector2.one*float.NegativeInfinity,high=Vector2.one*float.PositiveInfinity;
            for(int i=0;i<8;i++) {
                var point=inverse*(FramingMath.Corner(envelope,i)-focus)+Vector3.forward*distance;
                low=Vector2.Max(low,new Vector2(point.x-right*point.z,point.y-top*point.z));
                high=Vector2.Min(high,new Vector2(point.x-left*point.z,point.y-bottom*point.z));
            }
            float retreat=Mathf.Max(0,Mathf.Max((low.x-high.x)/Mathf.Max(.0001f,right-left),(low.y-high.y)/Mathf.Max(.0001f,top-bottom)));
            distance+=retreat;low-=new Vector2(right,top)*retreat;high-=new Vector2(left,bottom)*retreat;
            focus+=rotation*new Vector3(Mathf.Clamp(0,low.x,Mathf.Max(low.x,high.x)),Mathf.Clamp(0,low.y,Mathf.Max(low.y,high.y)),0);
        }
        public void SetProjection(Camera value,Bounds envelope,Rect viewport)
        {
            if(!value || envelope.size.sqrMagnitude<.0001f)return;
            envelope=PortraitEnvelope(envelope);
            bool changed=hasProjection && (Mathf.Abs(value.aspect-projectionAspect)>.0001f || region!=envelope || safe!=FramingMath.SafeFrame(viewport.x,viewport.y,viewport.width,viewport.height));
            if(changed)rotationOnly=false;
            // A layout update can arrive after ApplyFrame. Never derive the authored
            // pivot from a root that already contains the user's viewing transform.
            if(model && !applied)bodyPivot=model.TransformPoint(bodyPivotLocal);
            else if(!model)bodyPivot=envelope.center;
            camera=value;region=envelope;safe=FramingMath.SafeFrame(viewport.x,viewport.y,viewport.width,viewport.height);hasProjection=true;
            projectionAspect=camera.aspect;pitchAxis=camera.transform.right;screenUp=camera.transform.up;
            float depth=Mathf.Max(.1f,Vector3.Dot(region.center-camera.transform.position,camera.transform.forward));
            float height=2*depth*Mathf.Tan(camera.fieldOfView*Mathf.Deg2Rad*.5f);
            worldSpan=new Vector2(height*camera.aspect,height);
        }
        static bool Finite(Vector3 p) => float.IsFinite(p.x)&&float.IsFinite(p.y)&&float.IsFinite(p.z);
        public void Move(float horizontal) => Move(horizontal,0);
        public void Move(float horizontal,float vertical)
        {
            if(!Active || !Moving || !float.IsFinite(horizontal) || !float.IsFinite(vertical))return;
            var desired=gestureStart;
            desired.yaw=gestureStart.yaw-horizontal*360;
            desired.pitch=gestureStart.pitch-vertical*360;
            requested=desired;ConstrainTarget();
        }
        public void TransformView(float scale,float x,float y)
        {
            if(!Active || !Moving || !float.IsFinite(scale) || !float.IsFinite(x) || !float.IsFinite(y) || scale<=0)return;
            rotationOnly=false;requested.scale=Mathf.Clamp(gestureStart.scale*scale,.4f,MaximumScale);
            requested.x=Mathf.Clamp(gestureStart.x+x,-MaximumTranslation,MaximumTranslation);requested.y=Mathf.Clamp(gestureStart.y+y,-MaximumTranslation,MaximumTranslation);
            ConstrainTarget();
        }
        // Lifting a finger ends only that gesture. The editor and its draft stay alive.
        public void End()
        {
            Moving=false;LastReleasedYaw=Yaw;LastReleasedPitch=Pitch;
            if(Preparing) {Preparing=false;Assign(chargeBase);returning=true;}
        }
        public void ResetDraft() {if(!Active)return;Yaw=Mathf.DeltaAngle(0,Yaw);Pitch=Mathf.DeltaAngle(0,Pitch);ClearVelocity();rotationOnly=false;Moving=false;committed=CharacterViewPose.Default;Assign(committed);returning=true;}
        public void Load(CharacterViewPose pose,bool immediate=false)
        {
            if(!pose.Valid)return;
            rotationOnly=false;committed=Normalize(pose);Assign(committed);Preparing=false;Moving=false;returning=true;
            if(immediate) {Yaw=TargetYaw;Pitch=TargetPitch;Scale=TargetScale;Translation=TargetTranslation;ClearVelocity();}
        }
        public void Commit() { ConstrainTarget();committed=Target;requested=committed; }
        public void Close() { Commit();Active=Moving=Preparing=false;returning=true; }
        void ClearVelocity() {yawVelocity=pitchVelocity=scaleVelocity=0;translationVelocity=Vector2.zero;}
        static CharacterViewPose Normalize(CharacterViewPose p) => new CharacterViewPose {
            yaw=p.yaw,pitch=p.pitch,
            scale=Mathf.Clamp(p.scale,.4f,MaximumScale),x=Mathf.Clamp(p.x,-MaximumTranslation,MaximumTranslation),y=Mathf.Clamp(p.y,-MaximumTranslation,MaximumTranslation)};
        void Assign(CharacterViewPose pose) {requested=Normalize(pose);ApplyTarget(requested);}
        void ApplyTarget(CharacterViewPose pose) {TargetYaw=pose.yaw;TargetPitch=pose.pitch;TargetScale=pose.scale;TargetTranslation=new Vector2(pose.x,pose.y);}
        public void RestoreFrame()
        {
            if(applied && model) {model.rotation=authoredRotation;model.position=authoredPosition;model.localScale=authoredScale;}
            applied=false;
        }
        public void ResetImmediate()
        {
            RestoreFrame();rotationOnly=false;Active=Preparing=Moving=returning=false;Yaw=Pitch=chargeTime=0;Scale=1;Translation=Vector2.zero;
            Assign(CharacterViewPose.Default);ClearVelocity();
        }
        public bool Step(float deltaTime)
        {
            if(!float.IsFinite(deltaTime) || deltaTime<=0)return false;
            float dt=Mathf.Min(deltaTime,.05f),response=Moving ? .10f : .32f;
            if(Preparing)
            {
                chargeTime=Mathf.Min(HoldSeconds,chargeTime+dt);float p=chargeTime/HoldSeconds;
                requested.scale=chargeBase.scale*(1-.014f*Mathf.SmoothStep(0,1,p)+.004f*Mathf.Sin(p*Mathf.PI*3)*p);
            }
            ConstrainTarget();
            Yaw=Mathf.SmoothDamp(Yaw,TargetYaw,ref yawVelocity,response,Mathf.Infinity,dt);
            Pitch=Mathf.SmoothDamp(Pitch,TargetPitch,ref pitchVelocity,response,Mathf.Infinity,dt);
            int steps=Mathf.Max(1,Mathf.CeilToInt(dt/.008f));float h=dt/steps;
            for(int i=0;i<steps;i++) {scaleVelocity+=(230*(TargetScale-Scale)-24*scaleVelocity)*h;Scale+=scaleVelocity*h;}
            Scale=Mathf.Clamp(Scale,.4f,MaximumScale);
            Translation=Vector2.SmoothDamp(Translation,TargetTranslation,ref translationVelocity,response,Mathf.Infinity,dt);
            PeakYaw=Mathf.Max(PeakYaw,Mathf.Abs(Yaw));PeakPitch=Mathf.Max(PeakPitch,Mathf.Abs(Pitch));
            bool settled=Mathf.Abs(Yaw-TargetYaw)<.025f && Mathf.Abs(yawVelocity)<.1f && Mathf.Abs(Pitch-TargetPitch)<.025f && Mathf.Abs(pitchVelocity)<.1f && Mathf.Abs(Scale-TargetScale)<.0001f && Mathf.Abs(scaleVelocity)<.001f && (Translation-TargetTranslation).sqrMagnitude<.00000001f && translationVelocity.sqrMagnitude<.000001f;
            if(!Moving && !Preparing && settled)
            {
                Yaw=TargetYaw;Pitch=TargetPitch;Scale=TargetScale;Translation=TargetTranslation;ClearVelocity();
                if(returning){returning=false;ReturnCount++;return true;}
            }
            return false;
        }
        public void ConstrainTarget() { ApplyTarget(hasProjection && !rotationOnly && !requested.IsDefault ? Constrain(requested) : requested); }
        // Translation/scale limits use the authored portrait as a stable reference.
        // Free rotation may reveal the back or turn upside down; it must never
        // silently move/zoom the model to make a rotated silhouette fit.
        public CharacterViewPose Constrain(CharacterViewPose input,bool enforceMinimum=true)
        {
            var p=Normalize(input);if(!hasProjection)return p;
            float yaw=p.yaw,pitch=p.pitch;p.yaw=p.pitch=0;
            if(p.IsDefault) {p.yaw=yaw;p.pitch=pitch;return p;}
            var cameraMatrix=camera.transform.localToWorldMatrix;
            var angles=new Vector2(p.yaw,p.pitch);
            bool cached=fitCached && fitAngles==angles && fitCamera==cameraMatrix && fitRegion==region && fitSafe==safe && fitFov==camera.fieldOfView && fitAspect==camera.aspect;
            var maximum=p;maximum.scale=cached ? fitCeiling : MaximumScale;
            if(!cached)
            {
                if(!Intervals(maximum,out _,out _))
                {
                    float lo=.4f,hi=MaximumScale;
                    for(int i=0;i<18;i++) {maximum.scale=(lo+hi)*.5f;if(Intervals(maximum,out _,out _))lo=maximum.scale;else hi=maximum.scale;}
                    maximum.scale=lo;
                }
                fitCached=true;fitCeiling=maximum.scale;fitAngles=angles;fitCamera=cameraMatrix;fitRegion=region;fitSafe=safe;fitFov=camera.fieldOfView;fitAspect=camera.aspect;
            }
            // On a side view or a narrow safe window the fit ceiling changes. The
            // floor follows it, so a saved view cannot become a tiny figure on a
            // different phone. The normal portrait still has the .78 floor.
            float minimum=Mathf.Min(MinimumScale,maximum.scale*.8f);
            p.scale=Mathf.Clamp(p.scale,minimum,maximum.scale);
            Intervals(p,out var low,out var high);
            p.x=Mathf.Clamp(p.x,low.x,Mathf.Max(low.x,high.x));p.y=Mathf.Clamp(p.y,low.y,Mathf.Max(low.y,high.y));
            // A ratio alone is not a perceptual minimum after screen adaptation.
            // Raise the floor until the portrait occupies 30% of the safe height.
            for(int i=0;enforceMinimum && i<8;i++) {
                float height=Project(p).height,minimumHeight=safe.height*.3f;
                if(height>=minimumHeight || p.scale>=maximum.scale-.00001f)break;
                p.scale=Mathf.Min(maximum.scale,p.scale*minimumHeight/Mathf.Max(.01f,height)+.0005f);
                Intervals(p,out low,out high);
                p.x=Mathf.Clamp(p.x,low.x,Mathf.Max(low.x,high.x));p.y=Mathf.Clamp(p.y,low.y,Mathf.Max(low.y,high.y));
            }
            p.yaw=yaw;p.pitch=pitch;return p;
        }
        bool Intervals(CharacterViewPose pose,out Vector2 lower,out Vector2 upper)
        {
            float tan=Mathf.Tan(camera.fieldOfView*Mathf.Deg2Rad*.5f);
            float l=(safe.xMin*2-1)*tan*camera.aspect,r=(safe.xMax*2-1)*tan*camera.aspect;
            float b=(safe.yMin*2-1)*tan,t=(safe.yMax*2-1)*tan;
            lower=Vector2.one*-MaximumTranslation;upper=Vector2.one*MaximumTranslation;
            var q=Quaternion.AngleAxis(pose.pitch%360,pitchAxis)*Quaternion.AngleAxis(pose.yaw%360,Vector3.up);
            for(int i=0;i<8;i++)
            {
                var point=ViewPoint(FramingMath.Corner(region,i),q,pose.scale);
                point=camera.transform.InverseTransformPoint(point);
                if(point.z<camera.nearClipPlane*1.1f)return false;
                lower.x=Mathf.Max(lower.x,(l*point.z-point.x)/worldSpan.x);upper.x=Mathf.Min(upper.x,(r*point.z-point.x)/worldSpan.x);
                lower.y=Mathf.Max(lower.y,(point.y-t*point.z)/worldSpan.y);upper.y=Mathf.Min(upper.y,(point.y-b*point.z)/worldSpan.y);
            }
            return lower.x<=upper.x && lower.y<=upper.y;
        }
        public Rect Project(CharacterViewPose pose)
        {
            if(!hasProjection)return new Rect();
            Vector2 min=Vector2.one*float.PositiveInfinity,max=Vector2.one*float.NegativeInfinity;
            var q=Quaternion.AngleAxis(pose.pitch%360,pitchAxis)*Quaternion.AngleAxis(pose.yaw%360,Vector3.up);
            var shift=pitchAxis*pose.x*worldSpan.x-screenUp*pose.y*worldSpan.y;
            for(int i=0;i<8;i++)
            {
                Vector2 point=camera.WorldToViewportPoint(ViewPoint(FramingMath.Corner(region,i),q,pose.scale)+shift);
                min=Vector2.Min(min,point);max=Vector2.Max(max,point);
            }
            return Rect.MinMaxRect(min.x,min.y,max.x,max.y);
        }
        Vector3 ViewPoint(Vector3 point,Quaternion q,float scale) => region.center+(bodyPivot-region.center)*scale+q*(point-bodyPivot)*scale;
        public Vector3 DisplayPivot => ViewPoint(bodyPivot,Quaternion.identity,Scale)+pitchAxis*Translation.x*worldSpan.x-screenUp*Translation.y*worldSpan.y;
        public void ApplyFrame()
        {
            if(!model)return;
            ConstrainTarget();
            var p=Current;
            if(hasProjection && !p.IsDefault) {
                if(!rotationOnly)p=Constrain(p,!requested.IsDefault);
                Yaw=p.yaw;Pitch=p.pitch;Scale=p.scale;Translation=new Vector2(p.x,p.y);
            }
            ProjectedEnvelope=Project(p);
            if(p.IsDefault)return;
            authoredRotation=model.rotation;authoredPosition=model.position;authoredScale=model.localScale;
            var q=Quaternion.AngleAxis(Pitch%360,pitchAxis)*Quaternion.AngleAxis(Yaw%360,Vector3.up);
            var pivot=hasProjection ? bodyPivot : authoredPosition;
            model.rotation=q*authoredRotation;model.localScale=authoredScale*Scale;
            model.position=(hasProjection ? region.center+(pivot-region.center)*Scale : pivot)+q*(authoredPosition-pivot)*Scale+pitchAxis*Translation.x*worldSpan.x-screenUp*Translation.y*worldSpan.y;
            applied=true;
        }
    }
}
