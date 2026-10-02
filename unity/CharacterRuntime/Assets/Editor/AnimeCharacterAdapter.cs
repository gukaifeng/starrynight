using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEngine;

// Optional, data-only XCP extension. Existing characters and GLB imports retain
// their original material/animation setup; this only runs for declared support.
public static class AnimeCharacterAdapter
{
    [Serializable] sealed class MaterialData
    {
        public string name,texture,normal,matcap,matcapMask,emission,alphaMode,kind;
        public Color color,shadeColor,secondShadeColor,matcapColor,rimColor,emissionColor;
        public bool sourceShadow,sourceRim,matcapAdditive;
        public float cutoff,matcapStrength=-1,bumpScale=-1;
    }
    [Serializable] sealed class MaterialsData { public int schemaVersion;public string sourceProfile;public MaterialData[] materials; }
    public static void Prepare(ViewerCharacter character,string folder)
    {
        if(!character.Manifest.Supports("core.secondary-motion@1") && !character.Manifest.Supports("core.secondary-motion@2") && !character.Manifest.Supports("core.secondary-motion@3"))return;
        PrepareMaterials(character,folder);
        PrepareSecondary(character.gameObject,folder);
        // RestBounds otherwise sees the source T-pose, making conversation framing
        // too wide. Measure the actual first Idle frame, the pose shown on entry.
        var mesh=new Mesh();var bounds=new Bounds();bool first=true;
        foreach(var skin in character.GetComponentsInChildren<SkinnedMeshRenderer>(true))
        {
            skin.updateWhenOffscreen=false;skin.quality=SkinQuality.Bone4;
            skin.shadowCastingMode=UnityEngine.Rendering.ShadowCastingMode.On;skin.receiveShadows=true;
            if(!skin.enabled || !skin.gameObject.activeInHierarchy)continue;
            skin.BakeMesh(mesh,true);mesh.RecalculateBounds();
            for(int i=0;i<8;i++)
            {
                Vector3 corner=mesh.bounds.center+Vector3.Scale(mesh.bounds.extents,new Vector3((i&1)==0?-1:1,(i&2)==0?-1:1,(i&4)==0?-1:1));
                Vector3 point=character.transform.InverseTransformPoint(skin.transform.TransformPoint(corner));
                if(first){bounds=new Bounds(point,Vector3.zero);first=false;}else bounds.Encapsulate(point);
            }
        }
        UnityEngine.Object.DestroyImmediate(mesh);
        if(first)throw new Exception("ANIME_SKIN_MISSING");
        character.useAuthoredRestBounds=true;character.authoredRestBounds=bounds;
    }
    public static AvatarSecondaryMotion PrepareSecondary(GameObject model,string folder)
    {
        var data=JsonUtility.FromJson<SecondaryMotionData>(File.ReadAllText(folder+"/secondary-motion.json"));
        if((data.schemaVersion<1 || data.schemaVersion>3) || data.strands==null || data.strands.Length>(data.schemaVersion>=2?512:128) || data.colliders==null || data.colliders.Length>(data.schemaVersion>=2?256:64))
            throw new Exception("SECONDARY_MOTION_SCHEMA_INVALID");
        Transform Resolve(string path)
        {
            var t=CharacterContract.Resolve(model.transform,path);
            if(!t)throw new Exception("SECONDARY_MOTION_BONE_MISSING: "+path);
            return t;
        }
        var motion=model.GetComponent<AvatarSecondaryMotion>() ?? model.AddComponent<AvatarSecondaryMotion>();
        if(!float.IsFinite(data.ambientHairAngle) || data.ambientHairAngle<0 || data.ambientHairAngle>AvatarSecondaryMotion.MaxHairAngle ||
            !float.IsFinite(data.ambientClothAngle) || data.ambientClothAngle<0 || data.ambientClothAngle>AvatarSecondaryMotion.MaxClothAngle)
            throw new Exception("SECONDARY_MOTION_AMBIENT_ANGLE_INVALID");
        motion.ambientHairAngle=data.ambientHairAngle;
        motion.ambientClothAngle=data.ambientClothAngle;
        motion.strands=data.strands.Select(s=>{
            var bone=Resolve(s.bone);var tip=Resolve(s.tip);
            if(tip.parent!=bone || !float.IsFinite(s.angle) || s.angle<1 || s.angle>20 || !float.IsFinite(s.radius) || s.radius<0 || s.radius>.05f)
                throw new Exception("SECONDARY_MOTION_STRAND_INVALID");
            if(!new[]{null,"","none","hair","cloth"}.Contains(s.wind) || !float.IsFinite(s.windResponse) || s.windResponse<0 || s.windResponse>1)
                throw new Exception("SECONDARY_MOTION_WIND_INVALID");
            return new AvatarSecondaryMotion.Strand { bone=bone,tip=tip,rest=bone.localRotation,radius=s.radius,angle=s.angle,wind=s.wind,windResponse=s.windResponse };
        }).ToArray();
        motion.colliders=data.colliders.Select(s=>{
            if(s.localRadius && data.schemaVersion!=3)throw new Exception("SECONDARY_MOTION_RADIUS_SPACE_VERSION_INVALID");
            var bone=Resolve(s.bone);var scale=bone.lossyScale;
            float effectiveRadius=s.localRadius?s.radius*Mathf.Max(Mathf.Abs(scale.x),Mathf.Abs(scale.y),Mathf.Abs(scale.z))/Mathf.Max(Mathf.Abs(model.transform.lossyScale.x),.000001f):s.radius;
            if(!float.IsFinite(s.radius)||s.radius<0||!float.IsFinite(effectiveRadius)||effectiveRadius>.5f || !float.IsFinite(s.offset.sqrMagnitude))throw new Exception("SECONDARY_MOTION_COLLIDER_INVALID");
            return new AvatarSecondaryMotion.Sphere { bone=bone,offset=s.offset,radius=s.radius,localRadius=s.localRadius };
        }).ToArray();
        return motion;
    }
    public static void PrepareMaterials(ViewerCharacter character,string folder)
    {
        var source=JsonUtility.FromJson<MaterialsData>(File.ReadAllText(folder+"/materials.json"));
        if(source.schemaVersion==2) {PortableToonMaterialBuilder.Prepare(character.gameObject,folder);return;}
        if(source.schemaVersion!=1 || source.materials==null || source.materials.Length>32)throw new Exception("ANIME_MATERIAL_SCHEMA_INVALID");
        string target=folder+"/BakedMaterials";Directory.CreateDirectory(target);
        var materials=new System.Collections.Generic.Dictionary<string,Material>();
        foreach(var item in source.materials)
        {
            if(string.IsNullOrEmpty(item.name) || item.name.IndexOfAny(new[]{'/','\\'})>=0)throw new Exception("ANIME_MATERIAL_NAME_INVALID");
            string path=target+"/"+item.name+".mat";var material=AssetDatabase.LoadAssetAtPath<Material>(path);
            var shader=Shader.Find("Toon/Toon");if(!shader)throw new Exception("UNITY_TOON_SHADER_MISSING");
            if(!material) { material=new Material(shader);AssetDatabase.CreateAsset(material,path); }
            material.shader=shader;material.shaderKeywords=Array.Empty<string>();
            Texture2D Texture(string relative)
            {
                if(string.IsNullOrEmpty(relative))return null;
                if(!relative.StartsWith("textures/",StringComparison.Ordinal) || relative.Contains(".."))throw new Exception("ANIME_TEXTURE_PATH_INVALID");
                var texture=AssetDatabase.LoadAssetAtPath<Texture2D>(folder+"/"+relative);
                if(!texture)throw new Exception("ANIME_TEXTURE_MISSING: "+relative);return texture;
            }
            bool hair=item.kind=="hair" || item.name.Contains("HAIR"),
                skin=item.kind=="skin" || item.kind=="face" || item.name.Contains("SKIN"),
                eye=item.kind=="eye" || item.name.Contains("EYE"),
                face=item.kind=="face" || skin&&item.name.Contains("Face");
            var color=item.color.gamma;
            var albedo=Texture(item.texture);material.SetTexture("_MainTex",albedo);material.SetTexture("_BaseMap",albedo);
            if(item.kind=="glass")
            {
                // Lens coverage is continuous transparency. Clipping it at the
                // same threshold as lashes makes the glasses cover both eyes.
                material.shader=Shader.Find("Universal Render Pipeline/Lit");
                material.SetTexture("_BaseMap",albedo);material.SetColor("_BaseColor",color);
                material.SetFloat("_Surface",1);material.SetFloat("_Blend",0);
                material.SetFloat("_SrcBlend",5);material.SetFloat("_DstBlend",10);
                material.SetFloat("_ZWrite",0);material.SetFloat("_Cull",2);
                material.SetFloat("_Metallic",0);material.SetFloat("_Smoothness",.65f);
                material.SetFloat("_AlphaClip",0);material.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                material.SetOverrideTag("RenderType","Transparent");material.renderQueue=3000;
                material.SetShaderPassEnabled("ShadowCaster",false);
                EditorUtility.SetDirty(material);materials[item.name]=material;continue;
            }
            material.SetTexture("_1st_ShadeMap",albedo);material.SetTexture("_2nd_ShadeMap",albedo);
            material.SetColor("_BaseColor",color);material.SetColor("_Color",color);
            // Distinct skin/cloth/hair ramps retain the illustration's palette instead
            // of treating every surface as matte unlit plastic.
            var first=skin?new Color(1,.89f,.87f):eye?new Color(.97f,.98f,1):new Color(.72f,.77f,.9f);
            var second=skin?new Color(.87f,.7f,.73f):eye?new Color(.88f,.91f,1):new Color(.48f,.53f,.72f);
            material.SetColor("_1st_ShadeColor",color*first);material.SetColor("_2nd_ShadeColor",color*second);
            material.SetFloat("_Use_BaseAs1st",1);material.SetFloat("_Use_1stAs2nd",1);
            material.SetFloat("_BaseColor_Step",face?.52f:.5f);material.SetFloat("_BaseShade_Feather",skin?.28f:.16f);
            material.SetFloat("_ShadeColor_Step",.16f);material.SetFloat("_1st2nd_Shades_Feather",.2f);
            material.SetFloat("_Set_SystemShadowsToBase",face||eye?0:1);
            material.SetFloat("_Is_LightColor_Base",.35f);material.SetFloat("_Is_LightColor_1st_Shade",.25f);material.SetFloat("_Is_LightColor_2nd_Shade",.25f);
            material.SetFloat("_GI_Intensity",.08f);material.SetFloat("_Unlit_Intensity",.35f);
            material.SetFloat("_CullMode",0);material.SetFloat("_ZWriteMode",1);
            bool cutout=item.alphaMode!="OPAQUE";
            // UTS mode 1 samples a separate red mask; mode 2 supports albedo
            // alpha. Keep opaque depth/blending while clipping lashes and hair.
            material.SetFloat("_ClippingMode",cutout?2:0);material.SetFloat("_IsBaseMapAlphaAsClippingMask",1);
            material.SetFloat("_Clipping_Level",.5f-(item.alphaMode=="MASK"?Mathf.Clamp(item.cutoff,.1f,.5f):.12f));
            material.EnableKeyword(cutout?"_IS_CLIPPING_TRANSMODE":"_IS_CLIPPING_OFF");
            material.EnableKeyword(cutout?"_IS_OUTLINE_CLIPPING_YES":"_IS_OUTLINE_CLIPPING_NO");
            material.EnableKeyword("_OUTLINE_NML");material.EnableKeyword("_EMISSIVE_SIMPLE");
            // Preserve authored luminous hair strands instead of flattening
            // their color into the dark base texture. No emission is added to
            // models that did not author it.
            material.SetTexture("_Emissive_Tex",Texture(item.emission));
            material.SetColor("_Emissive_Color",string.IsNullOrEmpty(item.emission)?Color.black:item.emissionColor.gamma);
            material.SetFloat("_Outline_Width",eye||item.name.Contains("FACE")?0:face?.28f:.65f);
            material.SetColor("_Outline_Color",hair?new Color(.06f,.075f,.12f):new Color(.16f,.13f,.19f));
            material.SetFloat("_Farthest_Distance",12);material.SetFloat("_Nearest_Distance",.5f);
            material.SetFloat("_Is_BlendBaseColor",.65f);material.SetFloat("_Is_LightColor_Outline",.2f);
            material.SetTexture("_NormalMap",Texture(item.normal));material.SetFloat("_BumpScale",item.bumpScale>=0?item.bumpScale:hair?.45f:skin?.18f:.5f);
            material.SetFloat("_Is_NormalMapToBase",1);material.SetFloat("_Is_NormalMapToHighColor",1);
            material.SetColor("_HighColor",eye?new Color(.22f,.26f,.32f):hair?new Color(.10f,.13f,.19f):skin?new Color(.012f,.009f,.009f):new Color(.025f,.03f,.045f));
            material.SetFloat("_HighColor_Power",eye?.8f:hair?.55f:.35f);material.SetFloat("_Is_SpecularToHighColor",1);material.SetFloat("_Is_BlendAddToHiColor",1);
            material.SetFloat("_RimLight",eye?0:1);material.SetColor("_RimLightColor",hair?new Color(.16f,.2f,.3f):new Color(.07f,.09f,.13f));
            material.SetFloat("_RimLight_Power",.65f);material.SetFloat("_RimLight_InsideMask",.35f);
            material.SetFloat("_LightDirection_MaskOn",1);material.SetFloat("_Is_LightColor_RimLight",.5f);
            material.SetFloat("_MatCap",!string.IsNullOrEmpty(item.matcap) && (hair || item.matcapStrength>0)?1:0);material.SetTexture("_MatCap_Sampler",Texture(item.matcap));
            material.SetColor("_MatCapColor",item.matcapStrength>=0?item.matcapColor.gamma*item.matcapStrength:new Color(.35f,.40f,.52f));material.SetFloat("_Is_BlendAddToMatCap",1);
            material.SetFloat("_Is_LightColor_MatCap",0);material.renderQueue=cutout?2450:2000;
            material.SetOverrideTag("RenderType",cutout?"TransparentCutout":"Opaque");
            if(source.sourceProfile=="vrchat-liltoon-v1")
            {
                // Source-specific conversion; existing VRM assets retain their
                // reviewed shader settings. Toon smoothness is not PBR gloss.
                material.SetColor("_1st_ShadeColor",color*(item.sourceShadow?item.shadeColor.gamma:Color.white));
                material.SetColor("_2nd_ShadeColor",color*(item.sourceShadow?item.secondShadeColor.gamma:Color.white));
                material.SetColor("_HighColor",Color.black);
                material.SetFloat("_RimLight",item.sourceRim?1:0);
                material.SetColor("_RimLightColor",item.rimColor.gamma);
                material.SetTexture("_Set_MatcapMask",Texture(item.matcapMask));
                material.SetFloat("_Is_BlendAddToMatCap",item.matcapAdditive?1:0);
                material.SetFloat("_Outline_Width",eye||face?0:.32f);
            }
            EditorUtility.SetDirty(material);materials[item.name]=material;
        }
        foreach(var renderer in character.GetComponentsInChildren<Renderer>(true))
            renderer.sharedMaterials=renderer.sharedMaterials.Select(m=>materials.TryGetValue(m.name,out var replacement)?replacement:throw new Exception("ANIME_MATERIAL_UNMAPPED: "+m.name)).ToArray();
    }
}

public sealed class AnimeTextureImport : AssetPostprocessor
{
    void OnPreprocessTexture()
    {
        if(!assetPath.StartsWith("Assets/CharacterPackages/Imported/anime-",StringComparison.Ordinal) || !assetPath.Contains("/textures/"))return;
        var importer=(TextureImporter)assetImporter;
        bool normal=Path.GetFileName(assetPath).StartsWith("normal_",StringComparison.Ordinal);
        bool linear=Path.GetFileName(assetPath).StartsWith("linear_",StringComparison.Ordinal);
        importer.textureType=normal?TextureImporterType.NormalMap:TextureImporterType.Default;importer.sRGBTexture=!normal && !linear;importer.isReadable=false;
        importer.mipmapEnabled=true;importer.filterMode=FilterMode.Trilinear;importer.anisoLevel=4;
        // Preserve authored 4K detail for close portraits; this never upscales a
        // smaller source. ASTC and mipmaps still govern mobile memory/bandwidth.
        importer.maxTextureSize=4096;importer.alphaSource=TextureImporterAlphaSource.FromInput;importer.alphaIsTransparency=true;
        importer.textureCompression=TextureImporterCompression.CompressedHQ;
        importer.SetPlatformTextureSettings(new TextureImporterPlatformSettings { name="iPhone",overridden=true,maxTextureSize=4096,format=TextureImporterFormat.ASTC_4x4,compressionQuality=100 });
    }
}
