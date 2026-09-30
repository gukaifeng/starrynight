using System;
using System.Collections;
using System.Linq;
using System.Runtime.InteropServices;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public class BridgePayload
    {
        public bool immediate, immersive, transforming;
        public bool gesturesEnabled = true;
        // Optional for older hosts; new hosts send the framing lock independently of head taps.
        public bool framingGesturesEnabled = true;
        public bool nativeGestures;
        public float deltaX, deltaY, translationX, translationY, scale = 1;
        public int inspectionToken,previewToken;
        public bool previewFromConversation;
        public CharacterViewPose inspectionPose;
        public float topInset, bottomInset;
        public int targetFPS = 120;
        public string action, modelId, accent, ambience, state, framingShot, portraitKey;
        public float framingSize = 1, framingAngle;
        public float mouth, viewportX, viewportY, viewportWidth = 1, viewportHeight = 1;
        public float safeFrameX, safeFrameY, safeFrameWidth, safeFrameHeight;
        public StudioSettings studio;
        public CharacterSignal signal;
        public CharacterParameterValue[] parameters;
    }
    [Serializable] public class BridgeCommand
    {
        public int schemaVersion;
        public string kind, name, requestId;
        public int presentationId;
        public BridgePayload payload;
    }
    [Serializable] public class BridgeEvent
    {
        public int schemaVersion = 1;
        public string kind = "event", name, requestId = "", modelId = "studio-robot";
        public int presentationId;
        public float yaw, pitch, distance, defaultDistance;
        public string framingShot, effectiveShot;
        public float framingSize, framingAngle, headX, headY;
        public bool actionFraming;
        public bool gesturesEnabled, framingGesturesEnabled;
        public int nativeGestureRevision = 2;
        public bool nativeGestures;
        public bool framingMotionActive;
        public int inspectionGestureRevision=CharacterInspectionRotation.Revision,inspectionCount,inspectionRejectedCount,inspectionReturnCount;
        public bool inspectionActive,inspectionPreparing,inspectionMoving;
        public bool previewRotationActive;
        public bool previewScaleActive;
        public float previewScaleRatio,previewScaleMinimum,previewScaleMaximum,previewReactionIntensity;
        public int previewPinchCount,previewPinchReturnCount,previewPinchReactionCount;
        public string previewReactionKind;
        public int previewToken,previewRotationCount,previewRotationReturnCount;
        public int previewShakeCount;
        public float previewShakeIntensity;
        public float previewRotationYaw,previewRotationPitch,previewRotationPeakYaw,previewRotationPeakPitch;
        public float ambientTurnYaw,ambientTurnPitch,ambientTurnTravel;
        public int ambientTurnWaypoints;
        public bool ambientTurnSpeaking,ambientTurnSuppressed;
        public CharacterViewPose inspectionPose;
        public Rect inspectionEnvelope;
        public int inspectionToken;
        public float inspectionScale=1,inspectionTranslationX,inspectionTranslationY,idleTime,idleWeight;
        public bool idlePlaying;
        public float inspectionYaw,inspectionTargetYaw,inspectionPeakYaw,inspectionLastReleasedYaw;
        public float inspectionPitch,inspectionTargetPitch,inspectionPeakPitch,inspectionLastReleasedPitch;
        public int framingMotionRevision = CameraFramingMotion.Revision;
        public int layoutMotionRevision = 2;
        public int presentationRevision = 2;
        public int safeFramingRevision = 1;
        public int stableRenderedFrames;
        public Rect renderViewport, compositionArea;
        public Rect characterSafeFrame, framingEnvelopeViewport;
        public float framingTopClearance;
        public Vector3 cameraPosition;
        public int cameraSnapCount;
        public float sampleTime, cameraAspect, cameraFov;
        public float framingDistanceTarget, framingZoomVelocity;
        public string message = "";
        public string action = "", source = "";
        public StudioSettings studio;
        public EnvironmentState environment;
        public PostureState posture;
        public GazeState gaze;
        public CharacterPlatformState characterPlatform;
        public CharacterReceipt receipt;
        public string[] capabilities;
    }

    public static class OrbitMath
    {
        public const float DefaultYaw = 155f, DefaultPitch = 12f;
        public static float FitDistance(Bounds bounds, float aspect, float verticalFov)
        {
            float tangent = Mathf.Tan(verticalFov * Mathf.Deg2Rad * .5f);
            float horizontalRadius = new Vector2(bounds.extents.x, bounds.extents.z).magnitude;
            return Mathf.Max(bounds.extents.y * 1.65f / tangent,
                // Reserve horizontal room for the raised hand throughout its arc.
                horizontalRadius * 1.8f / (tangent * Mathf.Max(.2f, aspect))) + horizontalRadius;
        }
        public static float ClampPitch(float pitch) => Mathf.Clamp(pitch, -8f, 65f);
        public static float ClampDistance(float value, float minimum, float normal)
            => Mathf.Clamp(value, minimum, normal * 2.2f);
    }

    // Direct gestures and the precision panel share bounded framing; taps remain separate.
    public sealed class ViewerController : MonoBehaviour
    {
        public Transform model;
        public ViewerCharacter[] characters;
        public string[] resourceCharacterIDs=Array.Empty<string>();
        Coroutine pendingCharacterLoad;
        int characterLoadSequence;
        public Camera viewCamera;
        string activeModelId = "studio-robot";
        public string ActiveModelId => activeModelId;
        Bounds bounds, targetRegion;
        Bounds neutralPortrait;
        Vector3 neutralFace;
        float neutralFaceHeight;
        readonly CameraFramingMotion cameraMotion = new CameraFramingMotion();
        readonly CharacterInspectionRotation inspection = new CharacterInspectionRotation();
        Rect compositionArea = new Rect(0,0,1,1);
        Rect characterSafeFrame = new Rect(0,0,1,1);
        int cameraSnapCount;
        bool captureLayout;
        int layoutSamples;
        float nextLayoutSample;
        float motionResponse = CameraFramingMotion.ControlResponse, distanceTarget;
        ViewerCharacter character;
        string shot = "conversation";
        float size = 1, angle, currentSize = 1, currentAngle, distance, normal, lastAspect;
        int finger = -1, presentation, pinchFirst = -1, pinchSecond = -1;
        bool ready, actionFraming, initialized, multiGesture, immersive, hasSelectedModel;
        Vector2 tapOrigin, lastDragPosition;
        float pinchDistance;
        bool dragging, gestureDirty, suppressUntilRelease, gesturesEnabled = true;
        bool framingGesturesEnabled, nativeGestures;
        float tapTime;
        bool tapCandidate;
        int inspectionToken;
        bool inspectionCandidate;
        Vector2 inspectionOrigin;
        Coroutine pendingState;
        Coroutine pendingPresentation;
        int stableRenderedFrames;
        CharacterActions actions;
        CharacterPosture posture;
        CompanionAvatarDriver companion;
        CharacterGaze gaze;
        CharacterStudioDriver studio;
        CharacterDirector director;
        CharacterParameters parameters;
        CharacterReceipt receipt;
        string EffectiveShot => actionFraming ? "full" : shot;
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")] static extern void MSNativeSendEvent(string json);
#endif
        void Awake()
        {
            RenderCapabilityPolicy.ConfigureCamera(viewCamera);
            Application.targetFrameRate = 120;
            QualitySettings.vSyncCount = 0;
            Input.multiTouchEnabled = true;
            Input.simulateMouseWithTouches = false;
            if (!model || !viewCamera) { Emit("error", "", "模型场景引用缺失"); enabled = false; return; }
            actions = GetComponent<CharacterActions>();
            companion = gameObject.AddComponent<CompanionAvatarDriver>();
            gaze = gameObject.AddComponent<CharacterGaze>();
            gaze.OnHeadReactionCompleted=()=>Emit("headReactionCompleted");
            director=gameObject.AddComponent<CharacterDirector>();
            posture=gameObject.AddComponent<CharacterPosture>();
            posture.OnChanged=()=> { motionResponse=CameraFramingMotion.LayoutResponse;if(initialized) Reframe(false);Emit("postureConfigured"); };
            posture.OnSettled=()=>Emit("postureSettled");
            parameters=gameObject.AddComponent<CharacterParameters>();
            director.OnReceipt=r=> { receipt=r; Emit("characterReceipt"); receipt=null; };
            director.OnHostMotionChanged=()=>Emit("hostMotionChanged");
            studio = GetComponent<CharacterStudioDriver>();
            if(studio && studio.environment) studio.environment.OnSettled=()=>Emit("environmentConfigured");
            viewCamera.rect = new Rect(0,0,1,1);
            InitializeModel(); Reframe(true);
        }
        void InitializeModel()
        {
            inspection.Bind(model);
            director.ClearPerformance();
            gaze.RestorePose();
            companion.RestorePose();
            initialized = false; actionFraming = false;
            character = model.GetComponent<ViewerCharacter>();
            if (!character) throw new InvalidOperationException("模型目录缺失，请重新导出 Unity 工程");
            character.ApplyContract();
            activeModelId = character.modelId;
            actions?.Initialize(model, viewCamera, OnAction);
            posture.Bind(character,actions);
            bounds = character.RestBounds();
            neutralFaceHeight=character.portrait?.FaceHeight(character.transform) ?? 0;
            if(neutralFaceHeight>0) {neutralFace=character.portrait.Face(character.transform);neutralPortrait=character.portrait.Region(character.transform);}
            companion.Bind(model, viewCamera);
            if (studio) { studio.Bind(character); studio.Configure(new StudioSettings()); }
            gaze.Bind(model, viewCamera, actions);
            director.Bind(character,actions,companion,gaze); parameters.Bind(character);
            var performance=GetComponent<CharacterPerformanceDriver>();
            performance.OnChanged=()=>Emit("performanceConfigured");
            companion.Performance=performance;gaze.Performance=performance;
            actions.OnInteraction=id=> {
                var region=Array.Find(character.Manifest.interactions,r=>r.id==id);
                if(region==null)return false;
                int before=gaze.State.headReactionCount;
                var result=director.Local(region.eventName);
                return id=="head" ? gaze.State.headReactionCount>before : result.executed>0;
            };
            initialized = true;
        }
        void OnAction(string name, string action, string source)
        {
            actionFraming = name == "actionStarted" && character.Manifest.Action(action)?.framing == "full";
            motionResponse = actionFraming ? CameraFramingMotion.ActionResponse : CameraFramingMotion.ReturnResponse;
            if (initialized) Reframe(false);
            Emit(name, "", "", null, action, source);
            if (ready) ScheduleState();
        }
        void SelectModel(string id, string request)
        {
            var selected = Array.Find(characters ?? Array.Empty<ViewerCharacter>(), c => c && c.modelId == id);
            if (!selected) {
                if(!Array.Exists(resourceCharacterIDs,c=>c==id))throw new ArgumentException("此构建未包含所选模型，请重新导出 Unity 工程");
                if(pendingCharacterLoad!=null)StopCoroutine(pendingCharacterLoad);
                pendingCharacterLoad=StartCoroutine(LoadCharacter(id,request,++characterLoadSequence));return;
            }
            characterLoadSequence++;
            if(pendingCharacterLoad!=null) {StopCoroutine(pendingCharacterLoad);pendingCharacterLoad=null;}
            if(!hasSelectedModel && selected == character) {
                // Awake already bound the bundled default. Do not bind it a second time
                // on the first host handshake; all user settings follow before reveal.
                hasSelectedModel = true; Emit("modelSelected",request); return;
            }
            hasSelectedModel = true;
            if (pendingState != null) StopCoroutine(pendingState);
            pendingState = null; ClearInput(); inspection.ResetImmediate();
            foreach (var character in characters) character.gameObject.SetActive(character == selected);
            model = selected.transform;
            shot = "conversation"; size = 1; angle = 0;
            InitializeModel(); Reframe(true);
            GetComponent<RenderPerformance>().Configure(Application.targetFrameRate, presentation);
            Emit("modelSelected", request);
            if(Application.isPlaying && characters.Length>2)TrimCharacterCache(selected);
        }
        IEnumerator LoadCharacter(string id,string request,int sequence)
        {
            var load=Resources.LoadAsync<GameObject>("Characters/"+id);yield return load;
            if(sequence!=characterLoadSequence)yield break;
            pendingCharacterLoad=null;
            if(Array.Exists(characters,c=>c && c.modelId==id)) {SelectModel(id,request);yield break;}
            var asset=load.asset as GameObject;
            if(!asset) {Emit("error",request,"角色资源未能加载");yield break;}
            var instance=Instantiate(asset);instance.SetActive(false);
            var actor=instance.GetComponent<ViewerCharacter>();
            if(!actor || actor.modelId!=id) {Destroy(instance);Emit("error",request,"角色资源校验失败");yield break;}
            var list=new System.Collections.Generic.List<ViewerCharacter>(characters.Where(c=>c));list.Add(actor);characters=list.ToArray();
            SelectModel(id,request);
        }
        void TrimCharacterCache(ViewerCharacter keep)
        {
            var retained=characters.Where(c=>c && c!=keep).LastOrDefault();
            foreach(var c in characters)if(c && c!=keep && c!=retained)Destroy(c.gameObject);
            characters=retained?new[]{retained,keep}:new[]{keep};
            StartCoroutine(ReleaseCharacterResources());
        }
        IEnumerator ReleaseCharacterResources() {yield return null;yield return Resources.UnloadUnusedAssets();}
        IEnumerator PrewarmCharacter(BridgeCommand command)
        {
            string id=command.payload?.modelId;
            if(!Array.Exists(resourceCharacterIDs,c=>c==id)) {Emit("modelPrewarmFailed",command.requestId,"MODEL_UNAVAILABLE");yield break;}
            var load=Resources.LoadAsync<GameObject>("Characters/"+id);yield return load;
            if(command.presentationId!=presentation)yield break;
            var candidate=Array.Find(characters,c=>c && c.modelId==id);
            if(!candidate && load.asset is GameObject asset)
            {
                var instance=Instantiate(asset);instance.SetActive(false);candidate=instance.GetComponent<ViewerCharacter>();
                if(candidate) {characters=characters.Where(c=>c).Append(candidate).ToArray();if(characters.Length>2)TrimCharacterCache(character);}
                else Destroy(instance);
            }
            Emit(candidate?"modelPrewarmed":"modelPrewarmFailed",command.requestId,candidate?id:"MODEL_UNAVAILABLE");
        }
        IEnumerator Start()
        {
            yield return null;
            yield return new WaitForEndOfFrame();
            ready = true; Emit("sceneReady");
        }
        void Reframe(bool immediate)
        {
            lastAspect = viewCamera.aspect;
            targetRegion = EffectiveShot == "full" || (posture && posture.State.id!="stand")
                ? FramingMath.FullRegion(character.FramingBounds(actions.FramingClip))
                : neutralFaceHeight>0 ? neutralPortrait
                    : FramingMath.Region(bounds, "conversation", false,character.conversationStart);
            if(EffectiveShot!="full" && (!posture || posture.State.id=="stand"))
            {
                float authoredWidth=character.Manifest.rig.portraitWidthScale;
                if(!float.IsFinite(authoredWidth) || authoredWidth<=0)authoredWidth=1;
                targetRegion.size=new Vector3(targetRegion.size.x*Mathf.Clamp(authoredWidth,1,1.5f),targetRegion.size.y,targetRegion.size.z);
            }
            if (immediate) { currentSize = size; currentAngle = angle; }
            ApplyCamera(immediate);
        }
        void Update()
        {
            if (!viewCamera) return;
            inspection.RestoreFrame();
            HandleInput();
            int previewReturns=inspection.Preview.ReturnCount;
            int pinchReturns=inspection.Preview.PinchReturnCount;
            int previewReactions=inspection.Preview.ReactionCount;
            if(inspection.Step(Time.unscaledDeltaTime))Emit("inspectionReturned");
            director.SetHostMotionInteraction(inspection.Active || inspection.Preparing || inspection.Preview.Active || inspection.Preview.Pinching);
            if(previewReactions!=inspection.Preview.ReactionCount)Emit(inspection.Preview.ReactionKind=="shake" ? "characterShaken" : "characterPinched");
            inspection.Ambient.Step(Time.unscaledDeltaTime,
                ready && immersive && gesturesEnabled && !inspection.Active && !inspection.Preparing && !inspection.Preview.Active && !inspection.Preview.Pinching &&
                Mathf.Abs(inspection.Preview.ScaleRatio-1)<.0001f &&
                inspection.Preview.Offset.sqrMagnitude<.001f && string.IsNullOrEmpty(actions.CurrentAction) && (!posture || posture.State.id=="stand"),
                companion && companion.IsSpeaking);
            if(previewReturns!=inspection.Preview.ReturnCount)Emit("previewRotationReturned");
            if(pinchReturns!=inspection.Preview.PinchReturnCount)Emit("previewPinchReturned");
            float t = 1 - Mathf.Exp(-18f * Time.unscaledDeltaTime);
            currentSize = Mathf.Lerp(currentSize, size, t);
            currentAngle = Mathf.Lerp(currentAngle, angle, t);
            // Re-solving projection every frame handles aspect changes without discarding preferences.
            lastAspect = viewCamera.aspect;
            ApplyCamera(false, Time.unscaledDeltaTime);
        }
        void LateUpdate()
        {
            inspection.SetProjection(viewCamera,targetRegion,characterSafeFrame);
            inspection.ApplyFrame();
            // Explicit QA capture only, bounded to ten thousand samples; no frame bridge traffic
            // in ordinary launches and never an accessibility update per rendered frame.
            if (captureLayout && layoutSamples < 10000 && Time.unscaledTime >= nextLayoutSample)
            { nextLayoutSample = Time.unscaledTime + 1f/60; layoutSamples++; Emit("layoutMotionSample"); }
        }
        void HandleInput()
        {
            if (nativeGestures) return;
            int count = Input.touchCount;
            if (count == 0)
            {
#if UNITY_EDITOR || UNITY_STANDALONE
                if (finger != -2)
#endif
                { FinishGesture(); ClearInput(); }
                suppressUntilRelease = false;
            }
            if (!gesturesEnabled || suppressUntilRelease) return;
            if (count > 2)
            {
                // System multi-finger gestures must not become a pinch or a head tap.
                InterruptInput(); return;
            }
            if (count == 2)
            {
                EndInspection();inspectionCandidate=false;
                multiGesture = true; tapCandidate = false; finger = -1; dragging = false;
                if (!framingGesturesEnabled) return;
                var first = Input.GetTouch(0); var second = Input.GetTouch(1);
                if (!viewCamera.pixelRect.Contains(first.position) || !viewCamera.pixelRect.Contains(second.position) ||
                    first.phase == TouchPhase.Canceled || second.phase == TouchPhase.Canceled)
                { InterruptInput(); return; }
                if (first.phase == TouchPhase.Ended || second.phase == TouchPhase.Ended) return;
                float span = Vector2.Distance(first.position,second.position);
                bool samePair = (pinchFirst == first.fingerId && pinchSecond == second.fingerId) ||
                    (pinchFirst == second.fingerId && pinchSecond == first.fingerId);
                if (samePair && pinchDistance > 1 && span > 1)
                {
                    float next = FramingMath.Size(size * span / pinchDistance);
                    if (Mathf.Abs(next-size) > .00001f) motionResponse = CameraFramingMotion.ControlResponse;
                    gestureDirty |= Mathf.Abs(next-size) > .00001f; size = next;
                }
                pinchFirst = first.fingerId; pinchSecond = second.fingerId; pinchDistance = span;
                return;
            }
            if (count == 1)
            {
                // Once a second finger joined, lifting one never starts rotation / triggers a tap.
                if (multiGesture) return;
                var touch = Input.GetTouch(0);
                if (!viewCamera.pixelRect.Contains(touch.position) || touch.phase == TouchPhase.Canceled)
                { InterruptInput(); return; }
                if (touch.phase == TouchPhase.Began)
                {
                    finger = touch.fingerId; tapOrigin = lastDragPosition = touch.position;
                    tapTime = Time.unscaledTime; tapCandidate = true; dragging = false;
                    inspectionCandidate=true;
                }
                if (finger != touch.fingerId) return;
                DragTo(touch.position);
                if (touch.phase == TouchPhase.Ended)
                {
                    if (tapCandidate && !dragging && Time.unscaledTime-tapTime < .6f)
                        actions?.Tap(touch.position);
                    FinishGesture(); ClearInput(); ScheduleState();
                }
            }
#if UNITY_EDITOR || UNITY_STANDALONE
            else
            {
                Vector2 point = Input.mousePosition;
                if (Input.GetMouseButtonDown(0) && viewCamera.pixelRect.Contains(point))
                {
                    finger = -2; tapOrigin = lastDragPosition = point; tapTime = Time.unscaledTime;
                    tapCandidate = true; dragging = false;
                    inspectionCandidate=true;
                }
                if (finger == -2 && Input.GetMouseButton(0)) DragTo(point);
                if (finger == -2 && Input.GetMouseButtonUp(0))
                {
                    if (tapCandidate && !dragging && Time.unscaledTime-tapTime < .6f) actions?.Tap(point);
                    FinishGesture(); ClearInput(); ScheduleState();
                }
            }
#endif
        }
        void DragTo(Vector2 point)
        {
            var movement = point-tapOrigin;
            float threshold = Mathf.Min(Screen.width,Screen.height) * .026f;
            if(inspection.Active)
            {
                inspection.Move((point.x-inspectionOrigin.x)/Mathf.Max(1,Screen.width),
                    (inspectionOrigin.y-point.y)/Mathf.Max(1,Screen.height));
                tapCandidate=false;return;
            }
            if (movement.magnitude > threshold) {tapCandidate=false;inspectionCandidate=false;}
            if(inspectionCandidate && Time.unscaledTime-tapTime>=CharacterInspectionRotation.HoldSeconds)
            {
                inspectionCandidate=false;tapCandidate=false;inspectionOrigin=point;
                BeginInspection(point);return;
            }
            if (!framingGesturesEnabled) { lastDragPosition = point; return; }
            if (!dragging && Mathf.Abs(movement.x) > threshold) dragging = true;
            if (dragging)
            {
                float next = FramingMath.Angle(angle-(point.x-lastDragPosition.x)/Mathf.Max(1,Screen.width)*90f);
                if (Mathf.Abs(next-angle) > .0001f) motionResponse = CameraFramingMotion.ControlResponse;
                gestureDirty |= Mathf.Abs(next-angle) > .0001f; angle = next;
            }
            lastDragPosition = point;
        }
        void FinishGesture()
        {
            if (!gestureDirty) return;
            gestureDirty = false;
            // One durable update per gesture, not a native bridge event / disk write per frame.
            Emit("framingGestureEnded"); ScheduleState();
        }
        int previewToken;
        void HandleNativeGesture(BridgePayload value)
        {
            if (!nativeGestures || !gesturesEnabled || value == null || !viewCamera) return;
            if(value.action=="previewRotate" || value.action=="previewPinch")
            {
                bool pinching=value.action=="previewPinch";
                if(value.state=="began") {
                    // Native chat routing already chose blank space or a
                    // horizontal message drag. It acts as a character trackpad;
                    // direct scene touches still must hit the displayed mesh.
                    if(value.previewToken<=previewToken)return;
                    inspection.Preview.End();inspection.Preview.EndPinch();previewToken=value.previewToken;
                    if(!inspection.Active && !inspection.Preparing && actions &&
                       float.IsFinite(value.viewportX) && float.IsFinite(value.viewportY) &&
                       value.viewportX>=0 && value.viewportX<=1 && value.viewportY>=0 && value.viewportY<=1 &&
                       (value.previewFromConversation || HitDisplayedModel(new Vector2(value.viewportX*Screen.width,(1-value.viewportY)*Screen.height)))) {
                        if(pinching) {inspection.Preview.BeginPinch();inspection.Preview.Pinch(value.scale);Emit("previewPinchBegan");}
                        else {inspection.Preview.Begin();inspection.Preview.Move(value.deltaX,value.deltaY);Emit("previewRotationBegan");}
                    }
                    else Emit(pinching ? "previewPinchRejected" : "previewRotationRejected");
                }
                else if(value.previewToken==previewToken) {
                    if(value.state=="changed") {
                        if(pinching)inspection.Preview.Pinch(value.scale);else inspection.Preview.Move(value.deltaX,value.deltaY);
                        ScheduleState();
                    }
                    else if(value.state=="ended" || value.state=="cancelled") {
                        bool reacted=pinching ? inspection.Preview.EndPinch(value.state=="ended") : inspection.Preview.End(value.state=="ended");
                        Emit(pinching ? "previewPinchEnded" : "previewRotationEnded");
                        if(reacted)Emit(pinching ? "characterPinched" : "characterShaken");ScheduleState();
                    }
                }
                return;
            }
            if(value.action=="inspect")
            {
                if(value.state=="open") {
                    inspectionToken=value.inspectionToken;
                    if(inspection.Begin(viewCamera.transform.right))Emit("inspectionBegan");else Emit("inspectionRejected");
                }
                else if(value.state=="preparing")
                {
                    inspectionToken=value.inspectionToken;
                    if(float.IsFinite(value.viewportX) && float.IsFinite(value.viewportY) && value.viewportX>=0 && value.viewportX<=1 && value.viewportY>=0 && value.viewportY<=1 && actions && HitDisplayedModel(new Vector2(value.viewportX*Screen.width,(1-value.viewportY)*Screen.height)))
                    {inspection.Prepare();Emit("inspectionPrepared");}
                    else {inspection.Reject();Emit("inspectionRejected");}
                }
                else if(value.inspectionToken!=inspectionToken)return;
                else if(value.state=="began")
                {
                    ClearInput();
                    if(float.IsFinite(value.viewportX) && float.IsFinite(value.viewportY) && value.viewportX>=0 && value.viewportX<=1 && value.viewportY>=0 && value.viewportY<=1)
                        BeginInspection(new Vector2(value.viewportX*Screen.width,(1-value.viewportY)*Screen.height));
                }
                else if(value.state=="adjusting") {inspection.BeginAdjustment(value.transforming);Emit("inspectionAdjusting");}
                else if(value.state=="reset") {inspection.ResetDraft();Emit("inspectionChanged");ScheduleState();}
                else if(value.state=="capture") {inspection.Commit();Emit("inspectionCaptured");}
                else if(value.state=="close") {inspection.Close();Emit("inspectionClosed");ScheduleState();}
                else if(value.state=="changed") {
                    if(value.transforming)inspection.TransformView(value.scale,value.translationX,value.translationY);
                    else inspection.Move(value.deltaX,value.deltaY);
                    ScheduleState();
                }
                else if(value.state=="ended" || value.state=="cancelled")EndInspection();
                return;
            }
            if (value.action == "tap")
            {
                if (value.state == "ended" && value.viewportX >= 0 && value.viewportX <= 1 && value.viewportY >= 0 && value.viewportY <= 1)
                    actions?.Tap(new Vector2(value.viewportX*Screen.width,(1-value.viewportY)*Screen.height));
                return;
            }
            if (!framingGesturesEnabled) return;
            if (value.state == "began") { FinishGesture(); ClearInput(); }
            if (value.state != "cancelled")
            {
                if (value.action == "pan" && !float.IsNaN(value.deltaX) && !float.IsInfinity(value.deltaX))
                {
                    float next = FramingMath.Angle(angle-value.deltaX*90f);
                    gestureDirty |= Mathf.Abs(next-angle) > .0001f; angle = next;
                }
                if (value.action == "pinch" && value.scale > 0 && !float.IsNaN(value.scale) && !float.IsInfinity(value.scale))
                {
                    float next = FramingMath.Size(size*value.scale);
                    gestureDirty |= Mathf.Abs(next-size) > .00001f; size = next;
                }
                motionResponse = CameraFramingMotion.ControlResponse;
            }
            if (value.state == "ended" || value.state == "cancelled") { FinishGesture(); ClearInput(); ScheduleState(); }
        }
        void InterruptInput()
        {
            inspection.Preview.End();inspection.Preview.EndPinch();FinishGesture(); ClearInput(); suppressUntilRelease = Input.touchCount > 0;
        }
        bool HitDisplayedModel(Vector2 point)
        {
            bool applied=inspection.FrameApplied;
            if(!applied)inspection.ApplyFrame();
            bool hit=actions && actions.HitModel(point);
            if(!applied)inspection.RestoreFrame();
            return hit;
        }
        void BeginInspection(Vector2 point)
        {
            if(actions && HitDisplayedModel(point) && inspection.Begin(viewCamera.transform.right))
            {
                float depth=Vector3.Dot(model.position-viewCamera.transform.position,viewCamera.transform.forward);
                float height=2*Mathf.Max(.1f,depth)*Mathf.Tan(viewCamera.fieldOfView*Mathf.Deg2Rad*.5f);
                inspection.SetScreenSpace(viewCamera.transform.up,height*viewCamera.aspect,height);
                Emit("inspectionBegan");
            }
            else {inspection.Reject();Emit("inspectionRejected");}
        }
        void EndInspection()
        {
            if(!inspection.Active && !inspection.Preparing)return;
            inspection.End();inspection.Commit();Emit("inspectionEnded");ScheduleState();
        }
        void ScheduleState()
        {
            if (pendingState != null) StopCoroutine(pendingState);
            pendingState = StartCoroutine(ReportSettledState());
        }
        IEnumerator ReportSettledState()
        {
            yield return new WaitForSecondsRealtime(.12f);
            float deadline = Time.unscaledTime + 4;
            while (Time.unscaledTime < deadline && (!cameraMotion.Settled ||
                Mathf.Abs(currentSize-size) > .0001f || Mathf.Abs(currentAngle-angle) > .01f)) yield return null;
            Emit("state"); pendingState = null;
        }
        void ApplyCamera(bool immediate = false, float deltaTime = 0)
        {
            float targetPitch = immersive ? FramingMath.Pitch : FramingMath.CompositionPitch(compositionArea,viewCamera.fieldOfView);
            var rotation = Quaternion.Euler(targetPitch,FramingMath.FrontYaw+FramingMath.Angle(currentAngle),0);
            distanceTarget = FramingMath.Distance(targetRegion, rotation, viewCamera.aspect, viewCamera.fieldOfView, currentSize, viewCamera.nearClipPlane)*CharacterInspectionRotation.TurnFramingReserve;
            normal = FramingMath.Distance(targetRegion, rotation, viewCamera.aspect, viewCamera.fieldOfView, 1, viewCamera.nearClipPlane)*CharacterInspectionRotation.TurnFramingReserve;
            var focus = targetRegion.center;
            if (!immersive)
            {
                FramingMath.Compose(targetRegion,rotation,viewCamera.aspect,viewCamera.fieldOfView,
                    currentSize,viewCamera.nearClipPlane,compositionArea,out focus,out distanceTarget);
                FramingMath.Compose(targetRegion,rotation,viewCamera.aspect,viewCamera.fieldOfView,
                    1,viewCamera.nearClipPlane,compositionArea,out _,out normal);
            }
            if (immersive)
            {
                // Compose above the bottom conversation without cropping the room. Use the rest
                // envelope, not animated head tracking, so breathing and gestures don't move the camera.
                focus = FramingMath.ImmersiveFocus(targetRegion,bounds,character.conversationStart,rotation,
                    viewCamera.aspect,viewCamera.fieldOfView,distanceTarget);
                if(EffectiveShot!="full" && (!posture || posture.State.id=="stand") && neutralFaceHeight>0)
                {
                    CharacterPortrait.ComposeAt(neutralFace,neutralFaceHeight,rotation,viewCamera.aspect,viewCamera.fieldOfView,
                        currentSize,viewCamera.nearClipPlane,out focus,out distanceTarget);
                    CharacterPortrait.ComposeAt(neutralFace,neutralFaceHeight,rotation,viewCamera.aspect,viewCamera.fieldOfView,
                        1,viewCamera.nearClipPlane,out _,out normal);
                    inspection.ComposePortrait(targetRegion,neutralFace,rotation,
                        viewCamera.aspect,viewCamera.fieldOfView,characterSafeFrame,ref focus,ref distanceTarget);
                }
                if (posture && posture.State.id != "stand")
                {
                    // Wide, low poses occupy the chat header in landscape. Fit their complete
                    // envelope above it; interpolate the target through the existing camera spring.
                    float reclined = Mathf.InverseLerp(.95f,.5f,targetRegion.size.y / Mathf.Max(.01f,targetRegion.size.x))
                        * Mathf.InverseLerp(.85f,1.25f,viewCamera.aspect);
                    FramingMath.Compose(targetRegion,rotation,viewCamera.aspect,viewCamera.fieldOfView,
                        currentSize,viewCamera.nearClipPlane,new Rect(0,.28f,1,.72f),out var raisedFocus,out var raisedDistance);
                    focus = Vector3.Lerp(focus,raisedFocus,reclined);
                    distanceTarget = Mathf.Lerp(distanceTarget,raisedDistance,reclined);
                }
            }
            inspection.ConstrainComposition(targetRegion,rotation,viewCamera.aspect,viewCamera.fieldOfView,
                characterSafeFrame,ref focus,ref distanceTarget);
            // Smooth the final camera pose, including the portrait composition offset. Smoothing
            // bounds before the max/frustum solver creates speed kinks when a different axis wins.
            cameraMotion.SetTarget(focus,distanceTarget,targetPitch);
            if (immediate) { cameraMotion.Snap(); cameraSnapCount++; }
            else cameraMotion.Step(deltaTime,motionResponse);
            distance = cameraMotion.Distance;
            rotation = Quaternion.Euler(cameraMotion.Pitch,FramingMath.FrontYaw+FramingMath.Angle(currentAngle),0);
            // A yaw/layout spring can temporarily cross the constraint even when both
            // endpoints are safe. Apply the same continuous constraint to the displayed
            // pose, without changing the spring's state or the user's framing settings.
            var displayedFocus = cameraMotion.Focus;
            inspection.ConstrainComposition(targetRegion,rotation,viewCamera.aspect,viewCamera.fieldOfView,
                characterSafeFrame,ref displayedFocus,ref distance);
            viewCamera.transform.SetPositionAndRotation(displayedFocus - rotation * Vector3.forward * distance, rotation);
        }
        void ClearInput()
        {
            EndInspection();inspectionCandidate=false;
            finger = pinchFirst = pinchSecond = -1; pinchDistance = 0;
            tapCandidate = dragging = gestureDirty = multiGesture = false;
        }
        void OnApplicationPause(bool paused) { InterruptInput();if(paused)inspection.Close(); }
        void OnApplicationFocus(bool focus) { InterruptInput();if(!focus)inspection.Close(); }
        void OnDisable() { inspection.ResetImmediate(); }
        void ResetView(bool immediate, string request, int requestPresentation)
        {
            ClearInput(); actions?.ResetToIdle(); shot = "conversation"; size = 1; angle = 0;
            Reframe(immediate); ScheduleState();
            if (ready) Emit("viewReset", request, "", requestPresentation);
        }
        public void ReceiveCommand(string json)
        {
            try
            {
                if (string.IsNullOrEmpty(json) || json.Length > 8192) throw new ArgumentException("无效消息");
                var command = JsonUtility.FromJson<BridgeCommand>(json);
                if (command == null || command.schemaVersion != 1 || command.kind != "command")
                    throw new ArgumentException("不支持的协议");
                if (command.presentationId < presentation) return;
                presentation = command.presentationId;
                switch (command.name)
                {
                    case "selectModel": SelectModel(command.payload?.modelId, command.requestId); break;
                    case "prepareReveal":
                        if(pendingPresentation!=null) StopCoroutine(pendingPresentation);
                        pendingPresentation=StartCoroutine(PrepareReveal(command));
                        break;
                    case "captureLayoutMotion": captureLayout = true; layoutSamples = 0; break;
                    case "capturePortrait": StartCoroutine(CapturePortrait(command)); break;
                    case "prewarmModel":
                        // Render an isolated copy, never select/reset the user's retained actor.
                        // Native schedules one request only while the conversation is hidden.
                        var candidate = Array.Find(characters,c=>c && c.modelId==command.payload?.modelId);
                        if(candidate) {
                            try {
                                CharacterPortraitRenderer.Render(candidate,command.payload.studio,command.payload.parameters,command.payload.accent,false);
                                Emit("modelPrewarmed",command.requestId,command.payload.modelId);
                            } catch(Exception error) { Emit("modelPrewarmFailed",command.requestId,error.Message); }
                        } else StartCoroutine(PrewarmCharacter(command));
                        break;
                    case "getState": if (ready) Emit("state", command.requestId); break;
                    case "resetView": ResetView(command.payload != null && command.payload.immediate, command.requestId, presentation); break;
                    case "configureFraming":
                        // A panel's initial value / cancellation can arrive while the layout is still
                        // moving. Do not accelerate the unfinished long transition to control speed.
                        bool longTransition = shot != FramingMath.Shot(command.payload?.framingShot) ||
                            (!cameraMotion.Settled && motionResponse >= CameraFramingMotion.LayoutResponse);
                        motionResponse = longTransition ? CameraFramingMotion.LayoutResponse : CameraFramingMotion.ControlResponse;
                        shot = FramingMath.Shot(command.payload?.framingShot);
                        size = FramingMath.Size(command.payload?.framingSize ?? 1);
                        angle = FramingMath.Angle(command.payload?.framingAngle ?? 0);
                        ClearInput(); Reframe(command.payload != null && command.payload.immediate);
                        Emit("framingConfigured", command.requestId); ScheduleState(); break;
                    case "configureCompanion":
                        companion.Configure(command.payload?.accent, command.payload?.ambience);
                        Emit("companionConfigured", command.requestId); break;
                    case "configureStudio":
                        if (studio)
                        {
                            studio.Configure(command.payload?.studio,command.payload?.immediate ?? false);
                            bounds = character.RestBounds();
                            Reframe(false);
                        }
                        Emit("studioConfigured",command.requestId); break;
                    case "companionState": companion.SetState(command.payload?.state); break;
                    case "speechFrame": companion.SetMouth(command.payload?.mouth ?? 0); break;
                    case "conversationViewport":
                        var payload = command.payload;
                        if (payload != null)
                        {
                            immersive = payload.immersive;
                            motionResponse = CameraFramingMotion.LayoutResponse;
                            float x = Mathf.Clamp(payload.viewportX, 0, .9f), y = Mathf.Clamp(payload.viewportY, 0, .9f);
                            compositionArea = new Rect(x, y, Mathf.Clamp(payload.viewportWidth, .05f, 1-x), Mathf.Clamp(payload.viewportHeight, .05f, 1-y));
                            characterSafeFrame = FramingMath.SafeFrame(payload.safeFrameX,payload.safeFrameY,payload.safeFrameWidth,payload.safeFrameHeight);
                            companion.SetEnabled(true);
                            ClearInput(); ApplyCamera(); Emit("companionViewport", command.requestId); ScheduleState();
                        }
                        break;
                    case "configureViewport": InterruptInput(); motionResponse = CameraFramingMotion.LayoutResponse; ApplyCamera(); ScheduleState(); break;
                    case "configureGestures":
                        InterruptInput(); gesturesEnabled = command.payload?.gesturesEnabled ?? true;
                        framingGesturesEnabled = command.payload?.framingGesturesEnabled ?? true;
                        nativeGestures = command.payload?.nativeGestures ?? false;
                        ScheduleState(); break;
                    case "nativeGesture": HandleNativeGesture(command.payload); break;
                    case "loadCharacterView":
                        if(command.payload!=null)inspection.Load(command.payload.inspectionPose,command.payload.immediate);
                        Emit("inspectionLoaded");ScheduleState();break;
                    case "configurePerformance": GetComponent<RenderPerformance>().Configure(command.payload?.targetFPS ?? 120, presentation); break;
                    case "clearInput": InterruptInput(); break;
                    case "character.signal": director.Receive(command.payload?.signal); break;
                    case "character.parameters": parameters.Configure(command.payload?.parameters); Emit("parametersConfigured",command.requestId); break;
                    case "playAction": director.Local("action.request",command.payload?.action); break;
                    default: throw new ArgumentException("未知操作");
                }
            }
            catch (Exception e) { Debug.LogException(e); Emit("error", "", e.Message); }
        }
        IEnumerator PrepareReveal(BridgeCommand command)
        {
            // The host sends this fence AFTER appearance, room, posture and composition.
            // Wait for completed renders, not model selection or a guessed loading timer.
            string modelId=activeModelId;
            stableRenderedFrames=0;
            while(command.presentationId==presentation && modelId==activeModelId)
            {
                yield return new WaitForEndOfFrame();
                bool settled=ready && cameraMotion.Settled && (!posture || !posture.State.transitioning) &&
                    (!studio || !studio.environment || !studio.environment.State.transitioning);
                stableRenderedFrames=settled ? stableRenderedFrames+1 : 0;
                if(stableRenderedFrames<3) continue;
                Emit("presentationReady",command.requestId);
                pendingPresentation=null;
                yield break;
            }
            pendingPresentation=null;
        }
        IEnumerator CapturePortrait(BridgeCommand command)
        {
            var selected = character; int currentPresentation = presentation;
            yield return new WaitForEndOfFrame();
            if(selected!=character || currentPresentation!=presentation) yield break;
            try
            {
                string key = command.payload?.portraitKey;
                if(string.IsNullOrEmpty(key) || key.Length!=64 || !System.Text.RegularExpressions.Regex.IsMatch(key,"^[a-f0-9]+$"))
                    throw new ArgumentException("PORTRAIT_KEY_INVALID");
                byte[] png = CharacterPortraitRenderer.Render(selected,command.payload.studio,command.payload.parameters,command.payload.accent);
                string folder = System.IO.Path.Combine(Application.persistentDataPath,"CharacterPortraits");
                System.IO.Directory.CreateDirectory(folder);
                System.IO.File.WriteAllBytes(System.IO.Path.Combine(folder,key+".png"),png);
                Emit("portraitReady",command.requestId);
            }
            catch(Exception error) { Debug.LogWarning("Portrait deferred: "+error.Message); Emit("portraitFailed",command.requestId,error.Message); }
        }
        void Emit(string name, string request = "", string message = "", int? eventPresentation = null, string action = "", string source = "")
        {
            bool viewApplied=inspection.FrameApplied;
            if(!viewApplied)inspection.ApplyFrame();
            var headPoint = actions && initialized ? actions.HeadScreenPoint() : Vector2.zero;
            if(!viewApplied)inspection.RestoreFrame();
            var projectedEnvelope = FramingMath.ProjectedBounds(targetRegion,viewCamera);
            string json = JsonUtility.ToJson(new BridgeEvent { name = name, requestId = request, modelId = activeModelId,
                presentationId = eventPresentation ?? presentation, yaw = FramingMath.FrontYaw + currentAngle,
                pitch = cameraMotion.Pitch, distance = distance, defaultDistance = normal, message = message, action = action, source = source,
                framingShot = shot, effectiveShot = EffectiveShot, framingSize = size, framingAngle = angle, actionFraming = actionFraming,
                gesturesEnabled = gesturesEnabled, framingGesturesEnabled = framingGesturesEnabled, nativeGestures = nativeGestures,
                inspectionActive=inspection.Active,inspectionPreparing=inspection.Preparing,inspectionToken=inspectionToken,
                previewToken=previewToken,previewRotationActive=inspection.Preview.Active,
                previewScaleActive=inspection.Preview.Pinching,previewScaleRatio=inspection.Preview.ScaleRatio,
                previewScaleMinimum=inspection.Preview.MinimumObservedRatio,previewScaleMaximum=inspection.Preview.MaximumObservedRatio,
                previewPinchCount=inspection.Preview.PinchCount,previewPinchReturnCount=inspection.Preview.PinchReturnCount,
                previewPinchReactionCount=inspection.Preview.PinchReactionCount,previewReactionKind=inspection.Preview.ReactionKind,
                previewReactionIntensity=inspection.Preview.ReactionIntensity,
                previewRotationYaw=inspection.Preview.Offset.x,previewRotationPitch=inspection.Preview.Offset.y,
                ambientTurnYaw=inspection.Ambient.Offset.x,ambientTurnPitch=inspection.Ambient.Offset.y,
                ambientTurnTravel=inspection.Ambient.Travel,ambientTurnWaypoints=inspection.Ambient.Waypoints,
                ambientTurnSpeaking=inspection.Ambient.Speaking,ambientTurnSuppressed=inspection.Ambient.Suppressed,
                previewRotationPeakYaw=inspection.Preview.PeakYaw,previewRotationPeakPitch=inspection.Preview.PeakPitch,
                previewRotationCount=inspection.Preview.Count,previewRotationReturnCount=inspection.Preview.ReturnCount,
                previewShakeCount=inspection.Preview.ShakeCount,previewShakeIntensity=inspection.Preview.ShakeIntensity,
                inspectionPose=inspection.Target,inspectionMoving=inspection.Moving,inspectionEnvelope=inspection.ProjectedEnvelope,
                inspectionScale=inspection.Scale,inspectionTranslationX=inspection.Translation.x,inspectionTranslationY=inspection.Translation.y,
                idlePlaying=actions && actions.IdlePlaying,idleTime=actions ? actions.IdleTime : 0,idleWeight=actions ? actions.IdleWeight : 0,
                inspectionYaw=inspection.Yaw,inspectionTargetYaw=inspection.TargetYaw,
                inspectionPeakYaw=inspection.PeakYaw,inspectionLastReleasedYaw=inspection.LastReleasedYaw,
                inspectionPitch=inspection.Pitch,inspectionTargetPitch=inspection.TargetPitch,
                inspectionPeakPitch=inspection.PeakPitch,inspectionLastReleasedPitch=inspection.LastReleasedPitch,
                inspectionCount=inspection.Count,inspectionRejectedCount=inspection.RejectedCount,inspectionReturnCount=inspection.ReturnCount,
                framingMotionActive = !cameraMotion.Settled, framingDistanceTarget = distanceTarget,
                stableRenderedFrames = stableRenderedFrames,
                framingZoomVelocity = cameraMotion.ZoomVelocity,
                renderViewport = viewCamera.rect, compositionArea = compositionArea, cameraPosition = viewCamera.transform.position,
                characterSafeFrame = characterSafeFrame, framingEnvelopeViewport = projectedEnvelope,
                framingTopClearance = characterSafeFrame.yMax-projectedEnvelope.yMax,
                cameraSnapCount = cameraSnapCount, sampleTime = Time.unscaledTime, cameraAspect = viewCamera.aspect, cameraFov = viewCamera.fieldOfView,
                headX = headPoint.x / Mathf.Max(1, Screen.width), headY = 1 - headPoint.y / Mathf.Max(1, Screen.height),
                studio = studio ? studio.Current : null, environment = studio && studio.environment ? studio.environment.State : null, gaze = gaze ? gaze.State : null,posture=posture?posture.State:null,
                characterPlatform=director ? director.State : null,receipt=receipt,capabilities=CharacterContract.Capabilities });
#if UNITY_IOS && !UNITY_EDITOR
            MSNativeSendEvent(json);
#else
            Debug.Log("MODELSPACE_EVENT " + json);
#endif
        }
    }
}
