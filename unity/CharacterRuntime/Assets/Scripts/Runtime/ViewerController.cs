using System;
using System.Collections;
using System.Runtime.InteropServices;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public class BridgePayload
    {
        public bool immediate;
        public float topInset, bottomInset;
        public int targetFPS = 120;
        public string action;
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
        public string message = "";
        public string action = "", source = "";
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

    // One scene receiver and one camera controller. Touch motion never crosses the bridge.
    public sealed class ViewerController : MonoBehaviour
    {
        public Transform model;
        public Camera viewCamera;
        Bounds bounds;
        float yaw, pitch, distance, minimum, normal;
        float targetYaw, targetPitch, targetDistance;
        int lastTouches, finger = -1, presentation;
        Vector2 previous;
        float previousPinch, lastAspect;
        bool ready, resetting, mouseDown;
        float resetElapsed, startYaw, startPitch, startDistance;
        string resetRequest;
        int resetPresentation;
        Coroutine pendingState;
        CharacterActions actions;
        Vector2 tapOrigin;
        float tapTime;
        bool tapCandidate;
        bool multiGesture;

#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")] static extern void MSNativeSendEvent(string json);
#endif
        void Awake()
        {
            Application.targetFrameRate = 120;
            QualitySettings.vSyncCount = 0;
            Input.multiTouchEnabled = true;
            Input.simulateMouseWithTouches = false;
            if (!model || !viewCamera) { Emit("error", "", "模型场景引用缺失"); enabled = false; return; }
            var renderers = model.GetComponentsInChildren<Renderer>();
            if (renderers.Length == 0) { Emit("error", "", "模型没有可显示的内容"); enabled = false; return; }
            bounds = renderers[0].bounds;
            foreach (var renderer in renderers) bounds.Encapsulate(renderer.bounds);
            actions = GetComponent<CharacterActions>();
            if (actions) actions.Initialize(model,viewCamera,
                (name,action,source) => Emit(name, "", "", null, action, source));
            Reframe(false);
            ResetView(true, "", 0);
        }
        IEnumerator Start()
        {
            yield return null;
            yield return new WaitForEndOfFrame();
            ready = true;
            Emit("sceneReady");
        }
        void Reframe(bool preserve)
        {
            float ratio = normal > 0 ? targetDistance / normal : 1;
            lastAspect = viewCamera.aspect;
            normal = OrbitMath.FitDistance(bounds, lastAspect, viewCamera.fieldOfView);
            minimum = bounds.extents.magnitude * 1.08f + viewCamera.nearClipPlane;
            if (preserve)
            {
                targetDistance = OrbitMath.ClampDistance(normal * ratio, minimum, normal);
                distance = targetDistance;
            }
        }
        void Update()
        {
            if (!viewCamera) return;
            if (Mathf.Abs(lastAspect - viewCamera.aspect) > .002f) Reframe(true);
            if (resetting)
            {
                resetElapsed += Time.unscaledDeltaTime;
                float t = Mathf.SmoothStep(0, 1, Mathf.Clamp01(resetElapsed / .24f));
                yaw = Mathf.LerpAngle(startYaw, OrbitMath.DefaultYaw, t);
                pitch = Mathf.Lerp(startPitch, OrbitMath.DefaultPitch, t);
                distance = Mathf.Lerp(startDistance, normal, t);
                if (t >= 1) { resetting = false; Emit("viewReset", resetRequest, "", resetPresentation); }
            }
            else
            {
                HandleInput();
                float t = 1 - Mathf.Exp(-24f * Time.unscaledDeltaTime);
                yaw = Mathf.LerpAngle(yaw, targetYaw, t);
                pitch = Mathf.Lerp(pitch, targetPitch, t);
                distance = Mathf.Lerp(distance, targetDistance, t);
            }
            ApplyCamera();
        }
        void HandleInput()
        {
            int count = Input.touchCount;
            if (count >= 2) multiGesture = true;
            if (count == 0) multiGesture = false;
            if (lastTouches > 0 && count == 0)
            {
                ScheduleState();
            }
            if (count != lastTouches) { ClearInput(); lastTouches = count; }
            if (count == 1)
            {
                var touch = Input.GetTouch(0);
                if (touch.phase == TouchPhase.Canceled || touch.phase == TouchPhase.Ended)
                {
                    if (touch.phase == TouchPhase.Ended && tapCandidate && !multiGesture && Time.unscaledTime-tapTime < .4f
                        && Vector2.Distance(touch.position,tapOrigin) <= Mathf.Min(Screen.width,Screen.height)*.025f)
                        actions?.TapHead(touch.position);
                    ScheduleState(); ClearInput(); return;
                }
                if (finger != touch.fingerId)
                {
                    finger = touch.fingerId; previous = touch.position;
                    tapOrigin = touch.position; tapTime = Time.unscaledTime;
                    tapCandidate = touch.phase == TouchPhase.Began && !multiGesture; return;
                }
                if (Vector2.Distance(touch.position,tapOrigin) > Mathf.Min(Screen.width,Screen.height)*.025f) tapCandidate = false;
                if (!tapCandidate) Rotate(touch.position - previous);
                previous = touch.position;
            }
            else if (count >= 2)
            {
                var a = Input.GetTouch(0); var b = Input.GetTouch(1);
                if (a.phase == TouchPhase.Canceled || b.phase == TouchPhase.Canceled) { ClearInput(); return; }
                float separation = Vector2.Distance(a.position, b.position);
                if (previousPinch > 1 && separation > 1)
                    targetDistance = OrbitMath.ClampDistance(targetDistance * previousPinch / separation, minimum, normal);
                previousPinch = separation;
            }
#if UNITY_EDITOR || UNITY_STANDALONE
            else
            {
                if (Input.GetMouseButtonDown(0)) { mouseDown = true; previous = Input.mousePosition; tapOrigin = previous; tapTime = Time.unscaledTime; }
                if (Input.GetMouseButtonUp(0))
                {
                    if (Vector2.Distance((Vector2)Input.mousePosition,tapOrigin) < 10 && Time.unscaledTime-tapTime < .4f)
                        actions?.TapHead(Input.mousePosition);
                    mouseDown = false;
                }
                if (mouseDown) { Vector2 p = Input.mousePosition; Rotate(p - previous); previous = p; }
                targetDistance = OrbitMath.ClampDistance(targetDistance * Mathf.Exp(-Input.mouseScrollDelta.y * .08f), minimum, normal);
            }
#endif
        }
        void ScheduleState()
        {
            if (pendingState != null) StopCoroutine(pendingState);
            pendingState = StartCoroutine(ReportSettledState());
        }
        IEnumerator ReportSettledState()
        {
            yield return new WaitForSecondsRealtime(.4f);
            Emit("state");
            pendingState = null;
        }
        void Rotate(Vector2 delta)
        {
            targetYaw -= delta.x / Mathf.Max(Screen.width, 1) * 260f;
            targetPitch = OrbitMath.ClampPitch(targetPitch + delta.y / Mathf.Max(Screen.height, 1) * 160f);
        }
        void ApplyCamera()
        {
            Vector3 center = bounds.center;
            var direction = Quaternion.Euler(pitch, yaw, 0) * Vector3.back;
            viewCamera.transform.position = center + direction * distance;
            viewCamera.transform.LookAt(center);
        }
        void ClearInput() { finger = -1; previousPinch = 0; lastTouches = 0; mouseDown = false; tapCandidate = false; }
        void OnApplicationPause(bool paused) { ClearInput(); }
        void OnApplicationFocus(bool focus) { ClearInput(); }
        void ResetView(bool immediate, string request, int requestPresentation)
        {
            ClearInput();
            actions?.ResetToIdle();
            targetYaw = OrbitMath.DefaultYaw; targetPitch = OrbitMath.DefaultPitch; targetDistance = normal;
            resetRequest = request; resetPresentation = requestPresentation;
            if (immediate)
            {
                resetting = false; yaw = targetYaw; pitch = targetPitch; distance = normal;
                ApplyCamera();
                if (ready) Emit("viewReset", request, "", requestPresentation);
            }
            else
            {
                resetting = true; resetElapsed = 0;
                startYaw = yaw; startPitch = pitch; startDistance = distance;
            }
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
                    case "getState":
                        if (ready) Emit("state", command.requestId);
                        break;
                    case "resetView":
                        ResetView(command.payload != null && command.payload.immediate, command.requestId, presentation);
                        break;
                    case "configureViewport":
                        Reframe(true); break;
                    case "configurePerformance":
                        GetComponent<RenderPerformance>().Configure(command.payload?.targetFPS ?? 120, presentation); break;
                    case "clearInput": ClearInput(); break;
                    case "playAction": actions?.Play(command.payload?.action, "button"); break;
                    default: throw new ArgumentException("未知操作");
                }
            }
            catch (Exception e) { Emit("error", "", e.Message); }
        }
        void Emit(string name, string request = "", string message = "", int? eventPresentation = null, string action = "", string source = "")
        {
            string json = JsonUtility.ToJson(new BridgeEvent { name = name, requestId = request,
                presentationId = eventPresentation ?? presentation, yaw = yaw, pitch = pitch,
                distance = distance, defaultDistance = normal, message = message, action = action, source = source });
#if UNITY_IOS && !UNITY_EDITOR
            MSNativeSendEvent(json);
#else
            Debug.Log("MODELSPACE_EVENT " + json);
#endif
        }
    }
}
