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
        const string folder="Assets/Resources/Characters";Directory.CreateDirectory(folder);
        viewer.resourceCharacterIDs=viewer.characters.Select(c=>c.modelId).ToArray();
        foreach(var c in viewer.characters)
        {
            bool active=c.gameObject.activeSelf;c.gameObject.SetActive(false);
            PrefabUtility.SaveAsPrefabAsset(c.gameObject,folder+"/"+c.modelId+".prefab");
            c.gameObject.SetActive(active);
        }
        // Deactivated roster assets must not stay inside the Resources bundle.
        foreach(string file in Directory.GetFiles(folder,"*.prefab"))
            if(!viewer.resourceCharacterIDs.Contains(Path.GetFileNameWithoutExtension(file)))AssetDatabase.DeleteAsset(file);
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
