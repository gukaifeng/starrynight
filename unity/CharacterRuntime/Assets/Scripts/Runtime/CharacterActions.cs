using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    // Continuous transform clips work at both 60 and 120 rendered frames per second.
    public sealed class CharacterActions : MonoBehaviour
    {
        Animation animationPlayer;
        ViewerCharacter character;
        SkinnedMeshRenderer head;
        MeshFilter rigidHead;
        Camera viewCamera;
        Mesh hitMesh;
        Mesh inspectionMesh;
        Renderer[] inspectionRenderers=Array.Empty<Renderer>();
        MikuSecondaryMotion secondaryMotion;
        Action<string,string,string> report;
        Coroutine completion;
        float nextHeadTap;
        readonly HashSet<string> supported = new();
        public string CurrentAction { get; private set; } = "";
        public CharacterPosture Posture { get; set; }
        string restClip="Idle",playingClip="";
        public bool IdlePlaying => (character && character.GetComponent<AvatarControlDriver>() && character.GetComponent<AvatarControlDriver>().animator.enabled) || (animationPlayer && animationPlayer.enabled && animationPlayer.IsPlaying(restClip));
        public float IdleTime => animationPlayer && animationPlayer[restClip]!=null ? animationPlayer[restClip].time : 0;
        public float IdleWeight => animationPlayer && animationPlayer[restClip]!=null ? animationPlayer[restClip].weight : 0;
        public string FramingClip => string.IsNullOrEmpty(CurrentAction) ? restClip : playingClip;
        public bool CanPlay(string id) => supported.Contains(id) && (!Posture || !string.IsNullOrEmpty(Posture.ActionClip(id))) && (!Posture || !Posture.State.transitioning);

        public void Initialize(Transform model, Camera camera, Action<string,string,string> callback)
        {
            if (completion != null) StopCoroutine(completion);
            completion = null;
            if (animationPlayer) { animationPlayer.Stop(); animationPlayer.enabled = false; }
            ReleaseHitMesh();
            head = null; rigidHead = null; nextHeadTap = 0; supported.Clear();
            character = model.GetComponent<ViewerCharacter>();
            inspectionRenderers=model.GetComponentsInChildren<Renderer>(true);
            restClip="Idle";playingClip="";Posture=null;
            foreach (string action in character.actions)
                supported.Add(action);
            animationPlayer = model.GetComponentInChildren<Animation>(true);
            secondaryMotion = model.GetComponent<MikuSecondaryMotion>();
            var binding=CharacterContract.Resolve(model,model.GetComponent<ViewerCharacter>().Manifest.rig.headRenderer);
            head=binding ? binding.GetComponent<SkinnedMeshRenderer>() : null;
            rigidHead=binding ? binding.GetComponent<MeshFilter>() : null;
            if (!animationPlayer || (!head && !rigidHead)) throw new InvalidOperationException("角色动画或头部缺失");
            foreach (string clip in supported)
                if (!animationPlayer.GetClip(clip)) throw new InvalidOperationException("缺少动作 " + clip);
            if (!animationPlayer.GetClip("Idle")) throw new InvalidOperationException("缺少待机动作");
            viewCamera = camera; report = callback;
            hitMesh = new Mesh { name = "HeadInteractionSnapshot" };
            animationPlayer.playAutomatically = false;
            animationPlayer.enabled = true;
            animationPlayer.cullingType = AnimationCullingType.AlwaysAnimate;
            ResetToIdle();
        }
        public System.Func<string,bool> OnInteraction;
        public float Duration(string id) { string clip=Posture ? Posture.ActionClip(id) : id; return animationPlayer && !string.IsNullOrEmpty(clip) && animationPlayer.GetClip(clip) ? animationPlayer.GetClip(clip).length : 0; }
        public void SetRestClip(string clip)
        {
            if(completion!=null) StopCoroutine(completion);completion=null;
            restClip=clip;CurrentAction="";playingClip="";
            animationPlayer.Stop();animationPlayer[clip].wrapMode=WrapMode.Loop;animationPlayer[clip].time=0;animationPlayer.Play(clip);
            report?.Invoke("actionIdle","","posture");
        }
        public void ReturnToIdle()
        {
            if(!animationPlayer) return;
            if(completion!=null) StopCoroutine(completion);
            completion=null; CurrentAction=""; animationPlayer.CrossFade(restClip,.28f);
            report?.Invoke("actionIdle","","cancel");
        }
        public void ResetToIdle()
        {
            if (!animationPlayer) return;
            if (completion != null) StopCoroutine(completion);
            completion = null; CurrentAction = "";
            animationPlayer.Stop();
            animationPlayer[restClip].wrapMode = WrapMode.Loop;
            animationPlayer[restClip].time = 0;
            animationPlayer.Play(restClip);
            animationPlayer.Sample();
            // The portable avatar controller owns its layered baseline. Leaving
            // a second Legacy player active would overwrite masks and poses.
            var control=character.GetComponent<AvatarControlDriver>();
            if(control) {animationPlayer.Stop();animationPlayer.enabled=false;control.animator.enabled=true;}
            if (secondaryMotion) secondaryMotion.ResetSimulation();
            var avatarMotion=character.GetComponent<AvatarSecondaryMotion>();
            if(avatarMotion) avatarMotion.ResetSimulation();
            report?.Invoke("actionIdle", "", "reset");
        }
        public void Play(string action, string source)
        {
            if (string.IsNullOrEmpty(action) || !CanPlay(action))
                throw new ArgumentException("不支持的角色动作");
            if (completion != null) StopCoroutine(completion);
            playingClip=Posture ? Posture.ActionClip(action) : action;
            var state = animationPlayer[playingClip];
            state.wrapMode = WrapMode.ClampForever; state.time = 0; state.speed = 1;
            animationPlayer.CrossFade(playingClip, .32f);
            CurrentAction = action;
            report?.Invoke("actionStarted", action, source);
            completion = StartCoroutine(Finish(action, source, state.length));
        }
        IEnumerator Finish(string action, string source, float length)
        {
            yield return new WaitForSeconds(length);
            animationPlayer.CrossFade(restClip, .32f);
            CurrentAction = ""; completion = null;
            report?.Invoke("actionCompleted", action, source);
        }
        // Queried only for state events, never per frame. Uses the same animated mesh as hit testing.
        public Vector2 HeadScreenPoint()
        {
            if (!viewCamera) return Vector2.zero;
            if (head && hitMesh)
            {
                head.BakeMesh(hitMesh,false); hitMesh.RecalculateBounds();
                return viewCamera.WorldToScreenPoint(head.transform.TransformPoint(hitMesh.bounds.center));
            }
            return rigidHead ? (Vector2)viewCamera.WorldToScreenPoint(rigidHead.transform.TransformPoint(rigidHead.sharedMesh.bounds.center)) : Vector2.zero;
        }
        public bool Tap(Vector2 screenPoint)
        {
            if(Time.unscaledTime<nextHeadTap) return false;
            foreach(var region in character.Manifest.interactions)
            {
                if(region.id=="head" && region.renderer==character.Manifest.rig.headRenderer)
                { if(TapHead(screenPoint)) return true; continue; }
                var bone=CharacterContract.Resolve(character.transform,region.bone); if(!bone) continue;
                var ray=viewCamera.ScreenPointToRay(screenPoint);
                float distance=Vector3.Dot(bone.position-ray.origin,ray.direction);
                float radius=region.radius*Mathf.Abs(character.transform.lossyScale.x);
                if(distance<=0 || Vector3.Distance(ray.GetPoint(distance),bone.position)>radius) continue;
                if(OnInteraction?.Invoke(region.id)!=true)return false;
                nextHeadTap=Time.unscaledTime+.35f; return true;
            }
            return false;
        }
        // Once per recognized long press. Use the current visible triangles, not
        // the portrait rectangle or the rest bounds (which include empty room).
        // This deliberately does not dispatch a head interaction or author action.
        public bool HitModel(Vector2 screenPoint)
        {
            if(!character || !character.gameObject.activeInHierarchy || !viewCamera)return false;
            var worldRay=viewCamera.ScreenPointToRay(screenPoint);
            foreach(var renderer in inspectionRenderers)
            {
                if(!renderer || !renderer.enabled || !renderer.gameObject.activeInHierarchy)continue;
                // Imported skinned local/world bounds can be stale after a root
                // edit. The CPU-baked mesh below is the only authoritative culling
                // envelope. This runs only on hold hit tests, never per frame.
                var transform=renderer.transform;
                var ray=new Ray(transform.InverseTransformPoint(worldRay.origin),transform.InverseTransformVector(worldRay.direction));
                Mesh mesh;
                if(renderer is SkinnedMeshRenderer skin)
                {
                    if(!inspectionMesh)inspectionMesh=new Mesh {name="CharacterInspectionHitSnapshot"};
                    skin.BakeMesh(inspectionMesh,false);inspectionMesh.RecalculateBounds();mesh=inspectionMesh;
                }
                else
                {
                    var filter=renderer.GetComponent<MeshFilter>();
                    mesh=filter ? filter.sharedMesh : null;
                }
                if(!mesh || !mesh.isReadable)continue;
                if(!mesh.bounds.IntersectRay(ray))continue;
                var vertices=mesh.vertices;var indices=mesh.triangles;
                for(int i=0;i+2<indices.Length;i+=3)
                    if(HitTriangle(ray,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]))return true;
            }
            return false;
        }
        public bool TapHead(Vector2 screenPoint)
        {
            if (Time.unscaledTime < nextHeadTap || (!head && !rigidHead)) return false;
            // Bake only on a tap, so the ray follows the current animated head exactly.
            Mesh mesh;
            Transform headTransform;
            if (head) { head.BakeMesh(hitMesh,false); hitMesh.RecalculateBounds(); mesh=hitMesh; headTransform=head.transform; }
            else { mesh=rigidHead.sharedMesh; headTransform=rigidHead.transform; }
            var worldRay = viewCamera.ScreenPointToRay(screenPoint);
            var ray = new Ray(headTransform.InverseTransformPoint(worldRay.origin),
                headTransform.InverseTransformVector(worldRay.direction));
            bool hit=false;
            if(mesh.bounds.IntersectRay(ray))
            {
                var vertices = mesh.vertices; var indices = mesh.triangles;
                for (int i = 0; i < indices.Length; i += 3)
                    if(HitTriangle(ray, vertices[indices[i]], vertices[indices[i+1]], vertices[indices[i+2]])) { hit=true;break; }
            }
            // A head renderer can contain only facial surfaces: bangs and the crown often
            // belong to another renderer. A compact animated ellipsoid fills that gap,
            // without making long ponytails, shoulders or the whole renderer box tappable.
            if(!hit && !HitHeadEnvelope(ray,mesh.bounds)) return false;
            if(OnInteraction?.Invoke("head")!=true)return false;
            nextHeadTap = Time.unscaledTime + .35f;
            report?.Invoke("headTapped", "No", "head");
            return true;
        }
        static bool HitHeadEnvelope(Ray ray, Bounds face)
        {
            var radii=Vector3.Scale(face.extents,new Vector3(1.16f,1.65f,1.15f));
            var centre=face.center+Vector3.up*(face.size.y*.23f);
            if(Mathf.Min(radii.x,radii.y,radii.z)<.00001f) return false;
            var origin=ray.origin-centre;
            origin=new Vector3(origin.x/radii.x,origin.y/radii.y,origin.z/radii.z);
            var direction=new Vector3(ray.direction.x/radii.x,ray.direction.y/radii.y,ray.direction.z/radii.z);
            float a=Vector3.Dot(direction,direction), b=Vector3.Dot(origin,direction), c=Vector3.Dot(origin,origin)-1;
            float discriminant=b*b-a*c;
            return a>0 && discriminant>=0 && (-b+Mathf.Sqrt(discriminant))/a>0;
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
        void ReleaseHitMesh()
        {
            if(inspectionMesh)
            {
                if(Application.isPlaying)Destroy(inspectionMesh);else DestroyImmediate(inspectionMesh);
                inspectionMesh=null;
            }
            if(!hitMesh)return;
            if(Application.isPlaying)Destroy(hitMesh);else DestroyImmediate(hitMesh);
            hitMesh=null;
        }
        void OnDestroy() { ReleaseHitMesh(); }
    }
}
