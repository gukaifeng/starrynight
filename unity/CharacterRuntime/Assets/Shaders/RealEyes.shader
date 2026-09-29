Shader "Xiaoban/Real Eyes"
{
    Properties
    {
        _BaseMap("Eye texture",2D)="white"{}
        _BaseColor("Color",Color)=(1,1,1,1)
        _IrisTint("Iris",Color)=(.28,.15,.08,1)
        _Smoothness("Moisture",Range(0,1))=.84
        _Cutoff("Cutout",Range(0,1))=.36
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST; half4 _BaseColor; half4 _IrisTint; half _Smoothness; half _Cutoff;
            CBUFFER_END
            struct Attributes { float4 positionOS:POSITION; float3 normalOS:NORMAL; float2 uv:TEXCOORD0; };
            struct Varyings { float4 positionCS:SV_POSITION; float3 positionWS:TEXCOORD0; half3 normalWS:TEXCOORD1; float2 uv:TEXCOORD2; half fog:TEXCOORD3; };
            Varyings Vert(Attributes v)
            {
                Varyings o; VertexPositionInputs p=GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS=p.positionCS; o.positionWS=p.positionWS; o.normalWS=TransformObjectToWorldNormal(v.normalOS);
                o.uv=TRANSFORM_TEX(v.uv,_BaseMap); o.fog=ComputeFogFactor(p.positionCS.z); return o;
            }
            half4 Frag(Varyings v):SV_Target
            {
                half4 sample=SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,v.uv);
                clip(sample.a-_Cutoff);
                half3 tex=sample.rgb;
                half brightness=dot(tex,half3(.2126,.7152,.0722));
                half chroma=max(tex.r,max(tex.g,tex.b))-min(tex.r,min(tex.g,tex.b));
                half iris=saturate(chroma*8)*saturate((.85-brightness)*8);
                half3 albedo=lerp(tex,_IrisTint.rgb*lerp(.18,1.5,saturate(brightness*3)),iris)*_BaseColor.rgb;
                InputData input=(InputData)0;
                input.positionWS=v.positionWS; input.normalWS=normalize(v.normalWS);
                input.viewDirectionWS=GetWorldSpaceNormalizeViewDir(v.positionWS); input.shadowCoord=TransformWorldToShadowCoord(v.positionWS);
                input.bakedGI=SampleSH(input.normalWS); input.normalizedScreenSpaceUV=GetNormalizedScreenSpaceUV(v.positionCS); input.shadowMask=half4(1,1,1,1);
                SurfaceData surface=(SurfaceData)0; surface.albedo=albedo; surface.smoothness=_Smoothness;
                surface.normalTS=half3(0,0,1); surface.occlusion=1; surface.alpha=1;
                half4 color=UniversalFragmentPBR(input,surface); color.rgb=MixFog(color.rgb,v.fog); return color;
            }
            ENDHLSL
        }
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
    }
}
