using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;
using UnityEngine.SceneManagement;
using ModelSpace;

// Editor reviews keep every actor available. Player scene processing retains
// only the bundled default and loads other compiled prefabs on demand.
public sealed class CharacterResourceBuilder : IProcessSceneWithReport
{
    public int callbackOrder=>100;
    public static void Prepare(ViewerController viewer)
    {
        PrepareAtmospheres();
        const string folder="Assets/Resources/Characters";Directory.CreateDirectory(folder);
        Directory.CreateDirectory("Assets/DownloadableCharacters");
        AssetDatabase.Refresh();
        viewer.resourceCharacterIDs=viewer.characters.Select(c=>c.modelId).ToArray();
        foreach(var c in viewer.characters)
        {
            bool active=c.gameObject.activeSelf;c.gameObject.SetActive(false);
            string destination=CharacterBundleBuilder.Remote(c.modelId)?CharacterBundleBuilder.Prefab(c.modelId):folder+"/"+c.modelId+".prefab";
            string old=folder+"/"+c.modelId+".prefab";
            if(destination!=old && File.Exists(old) && !File.Exists(destination)) {
                string error=AssetDatabase.MoveAsset(old,destination);if(error!="")throw new Exception(error);
            }
            PrefabUtility.SaveAsPrefabAsset(c.gameObject,destination);
            if(destination!=old && File.Exists(old))AssetDatabase.DeleteAsset(old);
            c.gameObject.SetActive(active);
        }
        // Deactivated roster assets must not stay inside the Resources bundle.
        foreach(string file in Directory.GetFiles(folder,"*.prefab"))
            if(!viewer.resourceCharacterIDs.Contains(Path.GetFileNameWithoutExtension(file)))AssetDatabase.DeleteAsset(file);
    }
    public static void PrepareAtmospheres()
    {
        var active=CharacterPackageBuilder.Roster.characters.Where(id=>!CharacterBundleBuilder.Remote(id)).ToArray();
        const string folder="Assets/Resources/Atmospheres";
        const string archive="Assets/ArchivedAtmospheres";
        Directory.CreateDirectory(archive);
        AssetDatabase.Refresh();
        foreach(var path in AssetDatabase.GetSubFolders(folder))
        {
            string id=Path.GetFileName(path);
            if(active.Contains(id))continue;
            string destination=archive+"/"+id;
            if(AssetDatabase.IsValidFolder(destination))throw new Exception("Atmosphere archive collision: "+id);
            string error=AssetDatabase.MoveAsset(path,destination);
            if(!string.IsNullOrEmpty(error))throw new Exception(error);
        }
        // A restored roster can reuse the same archived, authored background.
        foreach(var id in active)
            if(AssetDatabase.IsValidFolder(archive+"/"+id) && !AssetDatabase.IsValidFolder(folder+"/"+id))
            {
                string error=AssetDatabase.MoveAsset(archive+"/"+id,folder+"/"+id);
                if(!string.IsNullOrEmpty(error))throw new Exception(error);
            }
        File.Copy(Path.Combine(CharacterPackageBuilder.Root,"ios/StarryNight/Resources/CharacterAtmospheres.json"),
            "Assets/Resources/CharacterAtmospheres.json",true);
        AssetDatabase.ImportAsset("Assets/Resources/CharacterAtmospheres.json",ImportAssetOptions.ForceSynchronousImport);
        AssetDatabase.SaveAssets();
        Directory.CreateDirectory("Assets/DownloadableAtmospheres");
        AssetDatabase.Refresh();
        foreach(string id in CharacterBundleBuilder.Policy.downloadOnly) {
            string source=archive+"/"+id,destination="Assets/DownloadableAtmospheres/"+id;
            if(AssetDatabase.IsValidFolder(source) && !AssetDatabase.IsValidFolder(destination)) {
                string error=AssetDatabase.MoveAsset(source,destination);if(error!="")throw new Exception(error);
            }
        }
    }
    public void OnProcessScene(Scene scene,BuildReport report)
    {
        if(report==null)return;
        var viewer=scene.GetRootGameObjects().SelectMany(g=>g.GetComponentsInChildren<ViewerController>(true)).FirstOrDefault();
        if(!viewer)return;
        if(viewer.resourceCharacterIDs==null || viewer.resourceCharacterIDs.Length!=CharacterPackageBuilder.Roster.characters.Length)
            throw new BuildFailedException("CHARACTER_RESOURCE_CATALOG_STALE");
        var initial=viewer.characters.Single(c=>c && c.transform==viewer.model);
        foreach(var c in viewer.characters)if(c && c!=initial)UnityEngine.Object.DestroyImmediate(c.gameObject);
        viewer.characters=new[]{initial};
        Debug.Log("CHARACTER_LAZY_SCENE_READY bundled=1 available="+viewer.resourceCharacterIDs.Length);
    }
}
