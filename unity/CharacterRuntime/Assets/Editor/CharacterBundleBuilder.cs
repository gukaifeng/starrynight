using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

/// Compiled data only: no author scripts, executable code or provider secrets.
public static class CharacterBundleBuilder
{
    [Serializable] public sealed class Delivery {public int schemaVersion;public string runtimeVersion;public string[] downloadOnly;}
    public static Delivery Policy=>JsonUtility.FromJson<Delivery>(File.ReadAllText(Path.Combine(CharacterPackageBuilder.Root,"assets/characters/delivery-policy.json")));
    public static bool Remote(string id)=>Policy.downloadOnly.Contains(id);
    public static string Prefab(string id)=>"Assets/DownloadableCharacters/"+id+".prefab";
    public static void BuildDevice()=>Build(false);
    public static void BuildSimulator()=>Build(true);
    public static void PrepareExisting() {
        UnityEditor.SceneManagement.EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ModelSpace.ViewerController>();
        CharacterResourceBuilder.Prepare(viewer);
        UnityEditor.SceneManagement.EditorSceneManager.SaveScene(viewer.gameObject.scene);
        AssetDatabase.SaveAssets();BuildIos.Validate();
        Debug.Log("CHARACTER_DELIVERY_SCENE_PREPARED");
    }
    static void Build(bool simulator)
    {
        PlayerSettings.iOS.sdkVersion=simulator?iOSSdkVersion.SimulatorSDK:iOSSdkVersion.DeviceSDK;
        string output=Path.Combine(CharacterPackageBuilder.Root,".local/character-delivery/bundles/"+(simulator?"ios-simulator":"ios"));
        Directory.CreateDirectory(output);
        var builds=Policy.downloadOnly.Select(id=>new AssetBundleBuild {
            assetBundleName=id+".bundle",
            assetNames=new[]{Prefab(id),"Assets/DownloadableAtmospheres/"+id+"/background.png"},
            addressableNames=new[]{"character","background"}
        }).ToArray();
        foreach(var build in builds)foreach(string asset in build.assetNames)
            if(!File.Exists(asset))throw new Exception("Missing downloadable resource: "+asset);
        var manifest=BuildPipeline.BuildAssetBundles(output,builds,BuildAssetBundleOptions.ChunkBasedCompression|BuildAssetBundleOptions.StrictMode,BuildTarget.iOS);
        if(!manifest)throw new Exception("Character bundle build failed");
        // Independent, self-contained bundles. A package must not depend on another role.
        foreach(string name in manifest.GetAllAssetBundles()) {
            if(manifest.GetAllDependencies(name).Length!=0)throw new Exception("Cross-character bundle dependency: "+name);
            uint crc;if(!BuildPipeline.GetCRCForAssetBundle(Path.Combine(output,name),out crc))throw new Exception("Missing bundle CRC");
            File.WriteAllText(Path.Combine(output,name+".crc"),crc.ToString());
        }
        Debug.Log("CHARACTER_BUNDLES_PASS platform="+(simulator?"ios-simulator":"ios")+" roles="+builds.Length);
    }
}
