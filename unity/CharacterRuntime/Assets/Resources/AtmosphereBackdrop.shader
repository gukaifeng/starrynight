Shader "StarryNight/AtmosphereBackdrop"
{
    Properties { _MainTex("Scene image",2D)="black" {} }
    SubShader
    {
        Tags {"RenderPipeline"="UniversalPipeline" "Queue"="Background" "RenderType"="Opaque"}
        Pass
        {
            ZWrite Off ZTest Always Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            TEXTURE2D(_MainTex);SAMPLER(sampler_MainTex);
            CBUFFER_START(UnityPerMaterial)
            float4 _Crop;float4 _Drift;
            CBUFFER_END
            struct Input {float4 positionOS:POSITION;float2 uv:TEXCOORD0;};
            struct Output {float4 positionCS:SV_POSITION;float2 uv:TEXCOORD0;};
            Output vert(Input input) {
                Output o;o.positionCS=float4(input.positionOS.xy,0,1);o.uv=input.uv;
                // A direct clip-space quad must follow Metal's top-origin UVs,
                // just like URP's full-screen triangle (there is no camera MVP).
                #if UNITY_UV_STARTS_AT_TOP
                o.uv.y=1-o.uv.y;
                #endif
                return o;
            }
            half4 frag(Output input):SV_Target
            {
                float depth=lerp(1.35,.45,input.uv.y);
                float2 uv=(input.uv-.5)*_Crop.xy+.5+_Drift.xy*depth;
                return half4(SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,uv).rgb,1);
            }
            ENDHLSL
        }
    }
}
