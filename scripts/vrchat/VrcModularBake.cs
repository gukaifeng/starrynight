// Runs only in the isolated official MA/NDMF stage, never in the shipping app.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Reflection;
using UnityEditor;
using UnityEngine;

public static class VrcModularBake
{
    [Serializable] sealed class Spec { public string role,fbx,prefab; }
    [Serializable] sealed class Config { public Spec[] specs; }
    [Serializable] sealed class Receipt
    {
        public int schemaVersion=1;
        public string role,sourcePrefab,bakedPrefab,status;
        public string[] dependencies,missingComponents,invalidMeshes,buildErrors;
        public int[] untouchedDefaultCalibrationLayers;
    }
    [Serializable] sealed class ReferenceEvidence {public ObjectEvidence[] objects;}
    [Serializable] sealed class ObjectEvidence {public string guid;public long fileID;public PointerEvidence[] references;}
    [Serializable] sealed class PointerEvidence {public string property,guid;public long fileID;}
    static void WriteReferenceEvidence(string root,string role,IEnumerable<string> dependencies)
    {
        var rows=new List<ObjectEvidence>();
        var controlTypes=new HashSet<string>{"AnimatorController","AnimatorState","AnimatorStateMachine",
            "AnimatorStateTransition","AnimatorTransition","BlendTree","AvatarMask"};
        foreach(var path in dependencies.Where(p=>p.EndsWith(".asset",StringComparison.Ordinal) &&
            (p.StartsWith("Assets/ZZZ_GeneratedAssets/",StringComparison.Ordinal) || p.StartsWith("Assets/StarryNightBaked/",StringComparison.Ordinal))))
        foreach(var asset in AssetDatabase.LoadAllAssetsAtPath(path))
        {
            if(!(asset is ScriptableObject) && !controlTypes.Contains(asset.GetType().Name))continue;
            if(!AssetDatabase.TryGetGUIDAndLocalFileIdentifier(asset,out string guid,out long fileID))continue;
            var pointers=new List<PointerEvidence>();
            using(var serialized=new SerializedObject(asset))
            {
                var property=serialized.GetIterator();bool enterChildren=true;
                while(property.Next(enterChildren))
                {
                    enterChildren=property.propertyType!=SerializedPropertyType.String;
                    if(property.propertyType!=SerializedPropertyType.ObjectReference || !property.objectReferenceValue)continue;
                    if(AssetDatabase.TryGetGUIDAndLocalFileIdentifier(property.objectReferenceValue,out string targetGuid,out long targetID))
                        pointers.Add(new PointerEvidence{property=property.propertyPath,guid=targetGuid,fileID=targetID});
                }
            }
            rows.Add(new ObjectEvidence{guid=guid,fileID=fileID,references=pointers.ToArray()});
        }
        File.WriteAllText(Path.Combine(root,"Inspection/Baked/"+role+"-references.json"),JsonUtility.ToJson(new ReferenceEvidence{objects=rows.ToArray()},true));
    }
    static void PersistTransientAssets(GameObject avatar,string role)
    {
        // Finish() can run before the generated container is visible to the
        // batch asset database. Use upstream's own traversal and asset saver
        // after that editing scope ends. This includes menus and behaviours,
        // not just meshes: otherwise a visually intact avatar loses controls.
        var assets=nadena.dev.ndmf.util.VisitAssets.ReferencedAssets(avatar,traverseSaved:true,includeScene:false)
            .Where(a=>a && !(a is MonoScript) && !EditorUtility.IsPersistent(a)).Distinct().ToArray();
        if(assets.Length==0)return;
        var folder="Assets/StarryNightBaked/"+role+"-data";
        Directory.CreateDirectory(folder);AssetDatabase.Refresh();
        var container=ScriptableObject.CreateInstance<nadena.dev.ndmf.runtime.GeneratedAssets>();
        AssetDatabase.CreateAsset(container,AssetDatabase.GenerateUniqueAssetPath(folder+"/generated.asset"));
        using(var saver=new nadena.dev.ndmf.SingleAssetSaver(container))
        {
            foreach(var asset in assets)saver.SaveAsset(asset);
        }
        AssetDatabase.SaveAssets();
        Debug.Log("VRC_MODULAR_PERSISTED_TRANSIENT_ASSETS "+assets.Length);
    }
    static string[] ReadBuildErrors()
    {
        // The pinned upstream exposes report contents but not its report list.
        // Read it only for validation; never patch plugins or suppress errors.
        var field=typeof(nadena.dev.ndmf.ErrorReport).GetField("Reports",BindingFlags.Static|BindingFlags.NonPublic);
        if(field?.GetValue(null) is not IEnumerable<nadena.dev.ndmf.ErrorReport> reports)
            throw new InvalidOperationException("Pinned NDMF report API changed; re-review the bake adapter");
        return reports.SelectMany(r=>r.Errors)
            .Where(e=>e.TheError.Severity>=nadena.dev.ndmf.ErrorSeverity.Error)
            .Select(e=>e.TheError.ToString()).ToArray();
    }
    public static void InspectBaked()
    {
        AssetDatabase.SaveAssets();AssetDatabase.Refresh();
        var path="InspectionConfig.json";var source=File.ReadAllText(path);
        var config=JsonUtility.FromJson<Config>(source);
        try
        {
            foreach(var spec in config.specs)spec.prefab="Assets/StarryNightBaked/"+spec.role+".prefab";
            File.WriteAllText(path,JsonUtility.ToJson(config,true));
            VrcPortableGeometry.Export();
        }
        finally {File.WriteAllText(path,source);}
        Debug.Log("VRC_MODULAR_INSPECTED");
    }
    public static void Run()
    {
        var root=Directory.GetParent(Application.dataPath).FullName;
        EditorSettings.serializationMode=SerializationMode.ForceText;
        var config=JsonUtility.FromJson<Config>(File.ReadAllText(Path.Combine(root,"InspectionConfig.json")));
        foreach(var spec in config.specs)
        {
            var original=AssetDatabase.LoadAssetAtPath<GameObject>(spec.prefab);
            if(!original)throw new InvalidOperationException("Missing audited prefab: "+spec.prefab);
            var descriptor=original.GetComponent<VRC.SDK3.Avatars.Components.VRCAvatarDescriptor>();
            if(!descriptor)throw new InvalidOperationException("Audited root has no avatar descriptor");
            var mergedLayers=original.GetComponentsInChildren<nadena.dev.modular_avatar.core.ModularAvatarMergeAnimator>(true)
                .Select(m=>(int)m.layerType).ToHashSet();
            var calibration=descriptor.specialAnimationLayers
                .Where(l=>l.isDefault && ((int)l.type==7 || (int)l.type==8) && !mergedLayers.Contains((int)l.type))
                .Select(l=>(int)l.type).ToArray();
            var baked=nadena.dev.ndmf.AvatarProcessor.ManualProcessAvatar(original);
            if(!baked)throw new InvalidOperationException("Official bake returned no avatar");
            try
            {
                PersistTransientAssets(baked,spec.role);
                var buildErrors=ReadBuildErrors();
                // Keep upstream's generated binary containers in place so
                // every GUID/fileID remains stable. A read-only type-tree
                // adapter indexes their control data after Unity exits.
                AssetDatabase.SaveAssets();AssetDatabase.Refresh();
                // Manual bake offsets its preview copy; portable geometry needs
                // the author's original root transform, not the preview offset.
                baked.transform.SetPositionAndRotation(original.transform.position,original.transform.rotation);
                baked.transform.localScale=original.transform.localScale;
                Directory.CreateDirectory("Assets/StarryNightBaked");AssetDatabase.Refresh();
                var path="Assets/StarryNightBaked/"+spec.role+".prefab";
                var saved=PrefabUtility.SaveAsPrefabAsset(baked,path);AssetDatabase.SaveAssets();
                var receipt=new Receipt {role=spec.role,sourcePrefab=spec.prefab,bakedPrefab=path,
                    status="requires-portable-inspection",
                    buildErrors=buildErrors,
                    untouchedDefaultCalibrationLayers=calibration,
                    dependencies=AssetDatabase.GetDependencies(path,true).OrderBy(x=>x).ToArray(),
                    invalidMeshes=saved.GetComponentsInChildren<SkinnedMeshRenderer>(true).Where(r=>!r.sharedMesh)
                        .Select(r=>AnimationUtility.CalculateTransformPath(r.transform,saved.transform)).ToArray(),
                    missingComponents=baked.GetComponentsInChildren<Transform>(true)
                        .Where(t=>t.GetComponents<Component>().Any(c=>!c)).Select(t=>AnimationUtility.CalculateTransformPath(t,baked.transform)).ToArray()};
                if(receipt.invalidMeshes.Length>0 || receipt.missingComponents.Length>0 || buildErrors.Length>0)receipt.status="invalid-baked-avatar";
                Directory.CreateDirectory(Path.Combine(root,"Inspection/Baked"));
                File.WriteAllText(Path.Combine(root,"Inspection/Baked/"+spec.role+".json"),JsonUtility.ToJson(receipt,true));
                WriteReferenceEvidence(root,spec.role,receipt.dependencies);
                Debug.Log("VRC_MODULAR_BAKE_RESULT "+spec.role+" status="+receipt.status+" dependencies="+receipt.dependencies.Length);
                if(buildErrors.Length>0)throw new InvalidOperationException("Official bake reported build errors; inspect receipt");
                if(receipt.missingComponents.Length>0)throw new InvalidOperationException("Missing source components remain after official bake; inspect receipt");
                if(receipt.invalidMeshes.Length>0)throw new InvalidOperationException("Official bake lost meshes; inspect receipt. Never activate this candidate.");
            }
            finally { UnityEngine.Object.DestroyImmediate(baked); }
        }
        InspectBaked();
    }
}
