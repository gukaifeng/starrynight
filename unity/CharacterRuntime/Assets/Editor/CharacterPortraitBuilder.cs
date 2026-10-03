using System.IO;
using ModelSpace;
using UnityEditor;
using UnityEngine;

public static class CharacterPortraitBuilder
{
    [System.Serializable] sealed class HostCatalog { public CharacterManifest[] characters; }
    public static void Export()
    {
        var scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene();
        if(scene.isDirty) throw new System.InvalidOperationException("Save the active scene before exporting portraits.");
        var viewer = Object.FindFirstObjectByType<ViewerController>();
        if(!viewer) throw new System.InvalidOperationException("Open ViewerScene before exporting portraits.");
        string native = Path.GetFullPath(Path.Combine(Application.dataPath,"../../../ios/StarryNight/Resources"));
        var catalog = JsonUtility.FromJson<HostCatalog>(File.ReadAllText(Path.Combine(native,"CharacterCatalog.json")));
        foreach(var model in viewer.characters)
        {
            string name = System.Array.Find(catalog.characters,c=>c.id==model.modelId).display.thumbnail + "Portrait";
            string folder = Path.Combine(native,"Assets.xcassets",name+".imageset");
            Directory.CreateDirectory(folder);
            File.WriteAllBytes(Path.Combine(folder,name+".png"),CharacterPortraitRenderer.Render(model,new StudioSettings(),null,"青绿"));
            File.WriteAllText(Path.Combine(folder,"Contents.json"),"{\"images\":[{\"filename\":\""+name+".png\",\"idiom\":\"universal\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}");
        }
        Debug.Log("PORTRAITS_EXPORTED "+viewer.characters.Length+" actual neutral head-and-shoulder renders");
    }
}
