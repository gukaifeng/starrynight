using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ModelSpace
{
    // Negotiate once before URP creates its attachments. A camera descriptor can
    // silently fall back to 1x while a renderer still uses the asset's 4x value;
    // align the runtime asset/backbuffer with the same hardware-supported result.
    public static class RenderCapabilityPolicy
    {
        [Serializable] sealed class Decision
        {
            public string device,graphicsAPI,colorFormat,depthFormat,reason;
            public int width,height,requestedSamples,supportedSamples,appliedSamples;
            public bool hdr,storeAndResolve,fxaa,simulatorFloatMSAAGuard;
        }
        static bool configured;
        static Decision decision;
        static UniversalRenderPipelineAsset runtimeAsset;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void Reset() {configured=false;decision=null;runtimeAsset=null;}
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void BeforeSceneLoad() {ConfigurePipeline();}

        static void ConfigurePipeline()
        {
            if(configured)return;
            var source=(QualitySettings.renderPipeline ?? GraphicsSettings.defaultRenderPipeline) as UniversalRenderPipelineAsset;
            if(!source)return; // ViewerController.Awake retries once scene resources exist.
            int requested=Mathf.Max(1,source.msaaSampleCount);
            var format=ColorFormat(source);
            var descriptor=new RenderTextureDescriptor(
                Mathf.Max(1,Mathf.RoundToInt(Screen.width*source.renderScale)),
                Mathf.Max(1,Mathf.RoundToInt(Screen.height*source.renderScale))) {
                graphicsFormat=format,depthStencilFormat=SystemInfo.GetGraphicsFormat(DefaultFormat.DepthStencil),
                msaaSamples=requested,sRGB=QualitySettings.activeColorSpace==ColorSpace.Linear,
                enableRandomWrite=false,bindMS=false,useDynamicScale=false
            };
            int supported=SystemInfo.GetRenderTextureSupportedMSAASampleCount(descriptor);
            int applied=Mathf.Clamp(supported,1,requested);
            // Match URP CreateRenderTextureDescriptor's store/resolve guard too.
            if(!SystemInfo.supportsStoreAndResolveAction)applied=1;
            // Verified iOS Simulator Metal limitation: the engine reports "Has Float
            // MSAA: 0" yet its public descriptor query returns 4 for B10G11R11 HDR.
            // The actual attachment is allocated with one sample. Treat this exact
            // simulator backend as single-sample HDR, irrespective of that false
            // positive. Real iPhones/iPads do not match this backend name.
            bool simulatorGuard=source.supportsHDR && Application.platform==RuntimePlatform.IPhonePlayer &&
                SystemInfo.graphicsDeviceType==GraphicsDeviceType.Metal &&
                SystemInfo.graphicsDeviceName.IndexOf("iOS simulator",StringComparison.OrdinalIgnoreCase)>=0;
            if(simulatorGuard)applied=1;
            bool fallback=applied<requested;
            if(fallback)
            {
                // Runtime clone only: the authoring asset remains HDR + 4x, including
                // builds running on real devices which actually support that descriptor.
                runtimeAsset=UnityEngine.Object.Instantiate(source);
                runtimeAsset.name=source.name+" (Runtime Capabilities)";
                runtimeAsset.hideFlags=HideFlags.DontSave;
                runtimeAsset.msaaSampleCount=applied;
                GraphicsSettings.defaultRenderPipeline=runtimeAsset;
                QualitySettings.renderPipeline=runtimeAsset;
                QualitySettings.antiAliasing=applied>1?applied:0;
            }
            decision=new Decision {device=SystemInfo.graphicsDeviceName,graphicsAPI=SystemInfo.graphicsDeviceType.ToString(),
                colorFormat=format.ToString(),depthFormat=descriptor.depthStencilFormat.ToString(),width=descriptor.width,height=descriptor.height,
                requestedSamples=requested,supportedSamples=supported,appliedSamples=applied,hdr=source.supportsHDR,
                storeAndResolve=SystemInfo.supportsStoreAndResolveAction,fxaa=fallback,simulatorFloatMSAAGuard=simulatorGuard,
                reason=simulatorGuard?"METAL_IOS_SIMULATOR_FLOAT_MSAA_UNSUPPORTED":!fallback?"AUTHORED_QUALITY_SUPPORTED":
                    !SystemInfo.supportsStoreAndResolveAction?"STORE_AND_RESOLVE_UNSUPPORTED":"COLOR_DEPTH_DESCRIPTOR_MSAA_LIMIT"};
            configured=true;
            Debug.Log("MODELSPACE_RENDER_CAPABILITIES "+JsonUtility.ToJson(decision));
        }
        static GraphicsFormat ColorFormat(UniversalRenderPipelineAsset pipeline)
        {
            // Matches installed URP 17's MakeRenderTextureGraphicsFormat. Its public
            // API does not expose the helper, so keep this small selection in sync.
            if(!pipeline.supportsHDR)return SystemInfo.GetGraphicsFormat(DefaultFormat.LDR);
            if(!Graphics.preserveFramebufferAlpha && pipeline.hdrColorBufferPrecision!=HDRColorBufferPrecision._64Bits &&
                SystemInfo.IsFormatSupported(GraphicsFormat.B10G11R11_UFloatPack32,GraphicsFormatUsage.Blend))
                return GraphicsFormat.B10G11R11_UFloatPack32;
            if(SystemInfo.IsFormatSupported(GraphicsFormat.R16G16B16A16_SFloat,GraphicsFormatUsage.Blend))
                return GraphicsFormat.R16G16B16A16_SFloat;
            return SystemInfo.GetGraphicsFormat(DefaultFormat.HDR);
        }
        public static void ConfigureCamera(Camera camera)
        {
            ConfigurePipeline();
            if(!camera || decision==null || !decision.fxaa)return;
            // HDR, lighting, shadows, resolution and the real-device quality tier
            // remain intact; FXAA covers edges when this GPU cannot do authored MSAA.
            camera.allowMSAA=decision.appliedSamples>1;
            var data=camera.GetUniversalAdditionalCameraData();
            data.antialiasing=AntialiasingMode.FastApproximateAntialiasing;
            data.renderPostProcessing=true;
            Debug.Log("MODELSPACE_RENDER_CAMERA camera="+camera.name+" msaa="+decision.appliedSamples+" fxaa=true hdr="+camera.allowHDR);
        }
    }
}
