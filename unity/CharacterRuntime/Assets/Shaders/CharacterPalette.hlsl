#ifndef STARRY_PALETTE_INCLUDED
#define STARRY_PALETTE_INCLUDED
// Apply a relative color family to the fully shaded result. The neutral path is
// exact, alpha/depth/blending are untouched, and highlights retain HDR range.
float3 StarryRGBToHSV(float3 c)
{
    float4 K = float4(0, -1.0/3.0, 2.0/3.0, -1);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b,c.g));
    float4 q = lerp(float4(p.xyw,c.r), float4(c.r,p.yzx), step(p.x,c.r));
    float d = q.x-min(q.w,q.y), e=1e-6;
    return float3(abs(q.z+(q.w-q.y)/(6*d+e)),d/(q.x+e),q.x);
}
float3 StarryHSVToRGB(float3 c)
{
    float3 p=abs(frac(c.xxx+float3(0,2.0/3.0,1.0/3.0))*6-3);
    return c.z*lerp(float3(1,1,1),saturate(p-1),c.y);
}
float3 StarryPaletteTone(float3 rgb,float4 tone)
{
    if (abs(tone.x)+abs(tone.y-1)+abs(tone.z)+abs(tone.w)<1e-6) return rgb;
    // Gamma-space hue rotation preserves the perceptual family of author art.
    float3 hsv=StarryRGBToHSV(pow(max(rgb,0),1.0/2.2));
    hsv.x=frac(hsv.x+tone.x);
    hsv.y=saturate(hsv.y*tone.y+tone.w*(1-hsv.y));
    if (hsv.y<0.001 && tone.w>0.001) hsv.x=frac(tone.x);
    return pow(max(StarryHSVToRGB(hsv),0),2.2)*exp2(tone.z);
}
float3 StarryPaletteGrade(float3 rgb)
{
    float luminance=dot(max(rgb,0),float3(.2126,.7152,.0722));
    float shadow=1-smoothstep(.05,.42,luminance);
    float highlight=smoothstep(.38,1.2,luminance);
    float3 main=StarryPaletteTone(rgb,_StarryPaletteMain);
    float3 dark=StarryPaletteTone(main,_StarryPaletteShadow);
    float3 light=StarryPaletteTone(main,_StarryPaletteHighlight);
    return lerp(lerp(main,dark,shadow),light,highlight);
}
#endif
