using System;
using System.Collections;
using UnityEngine;

namespace ModelSpace
{
    // The source GLB already owns these legacy clips; no duplicate animation assets.
    public sealed class CharacterActions : MonoBehaviour
    {
        Animation animationPlayer;
        SkinnedMeshRenderer head;
        Camera viewCamera;
        Mesh hitMesh;
        Action<string,string,string> report;
        Coroutine completion;
        float nextHeadTap;
        public string CurrentAction { get; private set; } = "";

        public void Initialize(Transform model, Camera camera, Action<string,string,string> callback)
        {
            animationPlayer = model.GetComponentInChildren<Animation>(true);
            foreach (var renderer in model.GetComponentsInChildren<SkinnedMeshRenderer>())
                if (renderer.name == "Head") head = renderer;
            if (!animationPlayer || !head) throw new InvalidOperationException("角色动画或头部缺失");
            foreach (string clip in new[] { "Idle", "Wave", "Jump", "Dance", "No" })
                if (!animationPlayer.GetClip(clip)) throw new InvalidOperationException("缺少动作 " + clip);
            viewCamera = camera; report = callback;
            hitMesh = new Mesh { name = "HeadInteractionSnapshot" };
            animationPlayer.playAutomatically = false;
            animationPlayer.enabled = true;
            animationPlayer.cullingType = AnimationCullingType.AlwaysAnimate;
            ResetToIdle();
        }
        public void ResetToIdle()
        {
            if (!animationPlayer) return;
            if (completion != null) StopCoroutine(completion);
            completion = null; CurrentAction = "";
            animationPlayer.Stop();
            animationPlayer["Idle"].wrapMode = WrapMode.Loop;
            animationPlayer["Idle"].time = 0;
            animationPlayer.Play("Idle");
            animationPlayer.Sample();
            report?.Invoke("actionIdle", "", "reset");
        }
        public void Play(string action, string source)
        {
            if (action != "Wave" && action != "Jump" && action != "Dance" && action != "No")
                throw new ArgumentException("不支持的角色动作");
            if (completion != null) StopCoroutine(completion);
            animationPlayer.Stop();
            var state = animationPlayer[action];
            state.wrapMode = WrapMode.ClampForever; state.time = 0; state.speed = 1;
            animationPlayer.Play(action);
            CurrentAction = action;
            report?.Invoke("actionStarted", action, source);
            completion = StartCoroutine(Finish(action, source, state.length));
        }
        IEnumerator Finish(string action, string source, float length)
        {
            yield return new WaitForSeconds(length);
            animationPlayer.CrossFade("Idle", .18f);
            CurrentAction = ""; completion = null;
            report?.Invoke("actionCompleted", action, source);
        }
        public bool TapHead(Vector2 screenPoint)
        {
            if (Time.unscaledTime < nextHeadTap || !head) return false;
            // Bake only on a tap, so the ray follows the current animated head exactly.
            head.BakeMesh(hitMesh);
            hitMesh.RecalculateBounds();
            var worldRay = viewCamera.ScreenPointToRay(screenPoint);
            var ray = new Ray(head.transform.InverseTransformPoint(worldRay.origin),
                head.transform.InverseTransformVector(worldRay.direction));
            if (!hitMesh.bounds.IntersectRay(ray)) return false;
            var vertices = hitMesh.vertices; var indices = hitMesh.triangles;
            for (int i = 0; i < indices.Length; i += 3)
            {
                if (!HitTriangle(ray, vertices[indices[i]], vertices[indices[i+1]], vertices[indices[i+2]])) continue;
                nextHeadTap = Time.unscaledTime + .35f;
                report?.Invoke("headTapped", "No", "head");
                Play("No", "head");
                return true;
            }
            return false;
        }
        static bool HitTriangle(Ray ray, Vector3 a, Vector3 b, Vector3 c)
        {
            Vector3 edge1 = b-a, edge2 = c-a, p = Vector3.Cross(ray.direction, edge2);
            float determinant = Vector3.Dot(edge1, p);
            if (Mathf.Abs(determinant) < .0000001f) return false;
            float inverse = 1 / determinant;
            Vector3 t = ray.origin-a;
            float u = Vector3.Dot(t,p) * inverse;
            if (u < 0 || u > 1) return false;
            Vector3 q = Vector3.Cross(t,edge1);
            float v = Vector3.Dot(ray.direction,q) * inverse;
            return v >= 0 && u+v <= 1 && Vector3.Dot(edge2,q) * inverse > 0;
        }
        void OnDestroy() { if (hitMesh) Destroy(hitMesh); }
    }
}
