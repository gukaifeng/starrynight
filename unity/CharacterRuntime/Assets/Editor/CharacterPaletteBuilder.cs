using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEngine;

public static class CharacterPaletteBuilder
{
    [Serializable] class MaterialList { public MaterialEntry[] materials; }
    [Serializable] class MaterialEntry { public string name,sourceName,shader; }
    const string LibraryPath="Assets/Resources/PaletteShaderLibrary.asset";
    public static void Prepare()
    {
        AssetDatabase.Refresh();
        var entries=new Dictionary<string,PaletteShaderEntry>();
        var labels=new Dictionary<string,PaletteMaterialLabel>();
        foreach(var role in CharacterPackageBuilder.Roster.characters)
        {
            string folder="Assets/CharacterPackages/Imported/"+role;
            string json=Path.Combine(folder,"materials.json");
            var list=JsonUtility.FromJson<MaterialList>(File.ReadAllText(json));
            foreach(var material in list.materials)
            {
                var shader=Shader.Find("StarryNight/Palette/"+material.shader);
                if(!shader)throw new Exception("Missing palette shader: "+material.shader);
                entries[material.shader]=new PaletteShaderEntry {original=material.shader,shader=shader};
                labels[material.name]=new PaletteMaterialLabel {key=material.name,label=material.sourceName};
            }
        }
        var library=AssetDatabase.LoadAssetAtPath<PaletteShaderLibrary>(LibraryPath);
        if(!library) {library=ScriptableObject.CreateInstance<PaletteShaderLibrary>();AssetDatabase.CreateAsset(library,LibraryPath);}
        library.entries=entries.Values.OrderBy(x=>x.original).ToArray();
        library.labels=labels.Values.OrderBy(x=>x.key).ToArray();
        EditorUtility.SetDirty(library);AssetDatabase.SaveAssets();
        foreach(var entry in library.entries)
            if(ShaderUtil.ShaderHasError(entry.shader))throw new Exception("Palette shader compilation failed: "+entry.original);
        Debug.Log("PALETTE_LIBRARY_READY families="+library.entries.Length+" labels="+library.labels.Length);
    }
    public static void ExportSimulator() {Prepare();BuildIos.ExportPreparedSimulator();}
    public static void ExportDevice() {Prepare();BuildIos.ExportPreparedDevice();}
}
