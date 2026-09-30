using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

// Restores typed author properties onto the pinned, host-owned MIT shader.
// Character packages never contain shaders or source code.
public static class PortableToonMaterialBuilder
{
    [Serializable] public class Number { public string name;public float value; }
    [Serializable] public class Tint { public string name;public Color value; }
    [Serializable] public class Image { public string name,path;public float[] scale,offset; }
    [Serializable] public class MaterialSpec { public string name,sourceName,shader;public int renderQueue;public Number[] floats;public Tint[] colors;public Image[] textures; }
    [Serializable] public class Catalog { public int schemaVersion;public string sourceProfile;public MaterialSpec[] materials; }
    public static void Prepare(GameObject character,string folder)
    {
        var data=JsonUtility.FromJson<Catalog>(File.ReadAllText(folder+"/materials.json"));
        if(data.schemaVersion!=2 || data.sourceProfile!="liltoon-properties-v1" || data.materials==null || data.materials.Length>256)throw new Exception("PORTABLE_MATERIAL_PROFILE_INVALID");
        string output=folder+"/BakedMaterials";Directory.CreateDirectory(output);
        var map=new Dictionary<string,Material>();
        foreach(var spec in data.materials)
        {
            if(!System.Text.RegularExpressions.Regex.IsMatch(spec.name??"",@"^mat_[a-f0-9]{32}$"))throw new Exception("PORTABLE_MATERIAL_ID_INVALID");
            if(string.IsNullOrEmpty(spec.shader) || !(spec.shader.StartsWith("lilToon",StringComparison.Ordinal) || spec.shader.StartsWith("Hidden/lilToon",StringComparison.Ordinal) || spec.shader.StartsWith("_lil/",StringComparison.Ordinal)))throw new Exception("UNAPPROVED_PORTABLE_SHADER");
            var shader=Shader.Find(spec.shader);if(!shader)throw new Exception("PINNED_LILTOON_SHADER_MISSING: "+spec.shader);
            string path=output+"/"+spec.name+".mat";
            var material=AssetDatabase.LoadAssetAtPath<Material>(path);
            if(!material) {material=new Material(shader);AssetDatabase.CreateAsset(material,path);}
            material.shader=shader;material.shaderKeywords=Array.Empty<string>();
            foreach(var number in spec.floats)
            {
                if(!float.IsFinite(number.value))throw new Exception("NONFINITE_MATERIAL_PROPERTY");
                if(material.HasProperty(number.name)) {
                    int index=shader.FindPropertyIndex(number.name);
                    if(index>=0 && shader.GetPropertyType(index)==UnityEngine.Rendering.ShaderPropertyType.Int)material.SetInteger(number.name,Mathf.RoundToInt(number.value));
                    else material.SetFloat(number.name,number.value);
                }
            }
            foreach(var tint in spec.colors)
                if(material.HasProperty(tint.name))material.SetColor(tint.name,tint.value);
            foreach(var image in spec.textures)
            {
                if(!image.path.StartsWith("textures/",StringComparison.Ordinal) || image.path.Contains("..") || image.path.Contains("\\"))throw new Exception("PORTABLE_TEXTURE_PATH_INVALID");
                var texture=AssetDatabase.LoadAssetAtPath<Texture2D>(folder+"/"+image.path);
                if(!texture)throw new Exception("PORTABLE_TEXTURE_MISSING: "+image.path);
                if(!material.HasProperty(image.name))continue;
                material.SetTexture(image.name,texture);
                if(image.scale?.Length==2)material.SetTextureScale(image.name,new Vector2(image.scale[0],image.scale[1]));
                if(image.offset?.Length==2)material.SetTextureOffset(image.name,new Vector2(image.offset[0],image.offset[1]));
            }
            material.renderQueue=spec.renderQueue;
            if(spec.shader.Contains("Multi"))
            {
                // Upstream deliberately sets autoReferenced=false. Call the
                // pinned Editor API without changing its package assembly.
                var utility=Type.GetType("lilToon.lilMaterialUtils, lilToon.Editor");
                var setup=utility?.GetMethod("SetupMultiMaterial",new[]{typeof(Material)});
                if(setup==null)throw new Exception("PINNED_LILTOON_MULTI_SETUP_MISSING");
                setup.Invoke(null,new object[]{material});
            }
            material.enableInstancing=true;
            EditorUtility.SetDirty(material);map.Add(spec.name,material);
        }
        foreach(var renderer in character.GetComponentsInChildren<Renderer>(true))
            renderer.sharedMaterials=renderer.sharedMaterials.Select(m=>m && map.TryGetValue(m.name,out var target)?target:throw new Exception("PORTABLE_MATERIAL_BINDING_MISSING")).ToArray();
    }
}
