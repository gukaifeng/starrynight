using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ModelSpace
{
    // One-shot derived asset. Never points the live camera at a different pose or changes its viewport.
    public static class CharacterPortraitRenderer
    {
        public const int Revision = 1;
        const int PortraitLayer = 30;
        public static byte[] Render(ViewerCharacter source, StudioSettings settings, CharacterParameterValue[] values, string accent, bool encode = true)
        {
            GameObject copy = null, cameraObject = null, keyObject = null, fillObject = null;
            RenderTexture target = null; Texture2D pixels = null;
            var meshes = new List<Mesh>();
            var lights = UnityEngine.Object.FindObjectsByType<Light>(FindObjectsSortMode.None);
            var masks = Array.ConvertAll(lights,l=>l.cullingMask);
            var active = RenderTexture.active;
            var fog = RenderSettings.fog; var mode = RenderSettings.ambientMode;
            var ambient = RenderSettings.ambientLight;
            try
            {
                copy = UnityEngine.Object.Instantiate(source.gameObject);
                copy.name = "PortraitOnly"; copy.hideFlags = HideFlags.HideAndDontSave;
                foreach(var behaviour in copy.GetComponentsInChildren<Behaviour>(true)) behaviour.enabled = false;
                copy.SetActive(true);
                var model = copy.GetComponent<ViewerCharacter>(); model.ApplyContract();
                var animation = copy.GetComponentInChildren<Animation>(true);
                if(animation && animation.GetClip("Idle")) animation.GetClip("Idle").SampleAnimation(copy,0);
                foreach(var skin in copy.GetComponentsInChildren<SkinnedMeshRenderer>(true))
                    for(int i=0;i<skin.sharedMesh.blendShapeCount;i++) skin.SetBlendShapeWeight(i,0);
                foreach(var renderer in copy.GetComponentsInChildren<Renderer>(true))
                    for(int i=0;i<renderer.sharedMaterials.Length;i++) renderer.SetPropertyBlock(null,i);
                copy.GetComponent<RealCharacterAppearance>()?.Configure(settings ?? new StudioSettings());
                var parameters = copy.AddComponent<CharacterParameters>();
                parameters.enabled = false; parameters.Bind(model); parameters.Configure(values); parameters.ApplyImmediately();
                ApplyAccent(model,accent);
                // Sampling animation may move its root; isolate it AFTER sampling.
                copy.transform.position = new Vector3(1000,1000,1000);
                foreach(var t in copy.GetComponentsInChildren<Transform>(true)) t.gameObject.layer = PortraitLayer;
                Bounds body = model.RestBounds();
                var head = CharacterContract.Resolve(copy.transform,model.Manifest.rig.headRenderer);
                Bounds face = MeshBounds(head,meshes);
                // Include the face, crown, distinctive hair and shoulder line without a room screenshot.
                float half = Mathf.Max(face.size.y*.92f,face.size.x*.65f,body.size.y*.195f);
                Vector3 focus = face.center - Vector3.up * (half*.18f);
                foreach(var skin in copy.GetComponentsInChildren<SkinnedMeshRenderer>())
                {
                    if(!skin.enabled) continue;
                    var mesh = new Mesh(); meshes.Add(mesh); skin.BakeMesh(mesh);
                    var baked = new GameObject("PortraitMesh"); baked.layer = PortraitLayer;
                    baked.transform.SetParent(skin.transform,false);
                    baked.AddComponent<MeshFilter>().sharedMesh = mesh;
                    var renderer = baked.AddComponent<MeshRenderer>(); renderer.sharedMaterials = skin.sharedMaterials;
                    var block = new MaterialPropertyBlock();
                    for(int slot=0;slot<skin.sharedMaterials.Length;slot++)
                    { skin.GetPropertyBlock(block,slot); renderer.SetPropertyBlock(block,slot); block.Clear(); }
                    skin.enabled = false;
                }
                for(int i=0;i<lights.Length;i++) lights[i].cullingMask &= ~(1<<PortraitLayer);
                bool toon=source.GetComponentsInChildren<Renderer>(true).Any(r=>r.sharedMaterials.Any(m=>m && m.shader.name=="Toon/Toon"));
                keyObject = PortraitLight("PortraitKey",new Vector3(24,145,0),toon?.85f:1.7f,new Color(1,.96f,.91f));
                fillObject = PortraitLight("PortraitFill",new Vector3(12,225,0),toon?.1f:.8f,new Color(.83f,.91f,1));
                RenderSettings.fog = false; RenderSettings.ambientMode = AmbientMode.Flat;
                RenderSettings.ambientLight = new Color(.62f,.65f,.63f);
                cameraObject = new GameObject("PortraitCamera"); cameraObject.hideFlags = HideFlags.HideAndDontSave;
                var camera = cameraObject.AddComponent<Camera>(); camera.enabled = false;
                camera.cullingMask = 1<<PortraitLayer; camera.clearFlags = CameraClearFlags.SolidColor;
                camera.backgroundColor = new Color(.865f,.91f,.878f,1); camera.orthographic = true;
                camera.orthographicSize = half; camera.aspect = 1; camera.nearClipPlane = .01f; camera.farClipPlane = 30;
                camera.allowHDR = false; camera.allowMSAA = true;
                camera.transform.position = focus + Quaternion.Euler(2,180,0)*Vector3.back*Mathf.Max(3,body.size.y*2);
                camera.transform.LookAt(focus);
                var data = camera.GetUniversalAdditionalCameraData(); data.renderPostProcessing = false;
                data.renderShadows = true; data.requiresColorOption = CameraOverrideOption.Off; data.requiresDepthOption = CameraOverrideOption.Off;
                target = new RenderTexture(512,512,24,RenderTextureFormat.ARGB32) { antiAliasing=4 };
                target.Create(); camera.targetTexture = target;
                var request = new UniversalRenderPipeline.SingleCameraRequest { destination=target };
                if(!RenderPipeline.SupportsRenderRequest(camera,request)) throw new InvalidOperationException("PORTRAIT_RENDER_UNSUPPORTED");
                RenderPipeline.SubmitRenderRequest(camera,request);
                if(!encode) return null; // GPU warmup needs neither ReadPixels nor PNG encoding.
                RenderTexture.active = target;
                pixels = new Texture2D(512,512,TextureFormat.RGB24,false);
                pixels.ReadPixels(new Rect(0,0,512,512),0,0); pixels.Apply();
                return pixels.EncodeToPNG();
            }
            finally
            {
                RenderTexture.active = active;
                RenderSettings.fog = fog; RenderSettings.ambientMode = mode; RenderSettings.ambientLight = ambient;
                for(int i=0;i<lights.Length;i++) if(lights[i]) lights[i].cullingMask = masks[i];
                if(copy) copy.SetActive(false);
                if(keyObject) keyObject.SetActive(false); if(fillObject) fillObject.SetActive(false);
                Dispose(copy); Dispose(cameraObject); Dispose(keyObject); Dispose(fillObject);
                foreach(var mesh in meshes) Dispose(mesh);
                Dispose(pixels); if(target) target.Release(); Dispose(target);
            }
        }
        static Bounds MeshBounds(Transform head,List<Mesh> temporary)
        {
            var skin = head.GetComponent<SkinnedMeshRenderer>();
            var mesh = skin ? new Mesh() : head.GetComponent<MeshFilter>().sharedMesh;
            if(skin) { temporary.Add(mesh); skin.BakeMesh(mesh); mesh.RecalculateBounds(); }
            var local = mesh.bounds; var result = new Bounds(head.TransformPoint(local.center),Vector3.zero);
            for(int i=0;i<8;i++) result.Encapsulate(head.TransformPoint(local.center + Vector3.Scale(local.extents,
                new Vector3((i&1)==0?-1:1,(i&2)==0?-1:1,(i&4)==0?-1:1))));
            return result;
        }
        static GameObject PortraitLight(string name,Vector3 rotation,float intensity,Color color)
        {
            var go = new GameObject(name); go.hideFlags = HideFlags.HideAndDontSave;
            var light = go.AddComponent<Light>(); light.type = LightType.Directional;
            light.cullingMask = 1<<PortraitLayer; light.intensity = intensity; light.color = color;
            light.shadows = LightShadows.Soft; go.transform.rotation = Quaternion.Euler(rotation); return go;
        }
        static void ApplyAccent(ViewerCharacter character,string accent)
        {
            if(character.Manifest.source.format!="builtin") return;
            Color tint = accent=="鸢紫" ? new Color(.83f,.58f,1) : accent=="暖金" ? new Color(1,.76f,.38f) : Color.white;
            var block = new MaterialPropertyBlock();
            foreach(var renderer in character.GetComponentsInChildren<Renderer>())
            for(int i=0;i<renderer.sharedMaterials.Length;i++)
            {
                var m=renderer.sharedMaterials[i];
                if(!m || !m.HasProperty("_BaseColor") || !(m.name.StartsWith("hair",StringComparison.OrdinalIgnoreCase) || m.name.StartsWith("Enamel") || m.name.StartsWith("Light"))) continue;
                renderer.GetPropertyBlock(block,i);
                block.SetColor("_BaseColor",tint==Color.white?m.GetColor("_BaseColor"):Color.Lerp(m.GetColor("_BaseColor"),tint,.72f));
                if(m.name.StartsWith("Light")) block.SetColor("_EmissionColor",(tint==Color.white?new Color(.2f,.85f,1):tint)*1.3f);
                renderer.SetPropertyBlock(block,i); block.Clear();
            }
        }
        static void Dispose(UnityEngine.Object value)
        {
            if(!value) return;
            if(Application.isPlaying) UnityEngine.Object.Destroy(value); else UnityEngine.Object.DestroyImmediate(value);
        }
    }
}
