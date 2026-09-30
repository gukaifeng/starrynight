using UnityEditor;

public sealed class AtmosphereTextureImporter:AssetPostprocessor
{
    void OnPreprocessTexture()
    {
        if(!assetPath.StartsWith("Assets/Resources/Atmospheres/")) return;
        var texture=(TextureImporter)assetImporter;
        texture.textureType=TextureImporterType.Default;texture.sRGBTexture=true;texture.mipmapEnabled=false;
        texture.isReadable=false;texture.maxTextureSize=2048;texture.wrapMode=UnityEngine.TextureWrapMode.Clamp;
        texture.filterMode=UnityEngine.FilterMode.Bilinear;
        var ios=texture.GetPlatformTextureSettings("iPhone");ios.overridden=true;ios.maxTextureSize=2048;
        ios.format=TextureImporterFormat.ASTC_6x6;ios.compressionQuality=100;texture.SetPlatformTextureSettings(ios);
    }
}
