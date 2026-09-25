using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering.Universal;

// Environment validation only. This does not implement or build the V0 app.
public static class DependencyReadiness
{
    public static void Check()
    {
        if (!BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.iOS, BuildTarget.iOS))
            throw new InvalidOperationException("The installed Editor cannot use iOS Build Support.");

        RequirePackage("com.unity.render-pipelines.universal", "17.3.0");
        RequirePackage("com.unity.cloud.gltfast", "6.16.1");

        const string modelPath = "Assets/ThirdParty/RobotExpressive/RobotExpressive.glb";
        AssetDatabase.ImportAsset(modelPath, ImportAssetOptions.ForceSynchronousImport);
        var model = AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
        if (model == null)
            throw new InvalidOperationException("glTFast did not import RobotExpressive as a GameObject.");

        var renderers = model.GetComponentsInChildren<Renderer>(true);
        if (renderers.Length == 0)
            throw new InvalidOperationException("The imported model contains no renderers.");
        foreach (var renderer in renderers)
        foreach (var material in renderer.sharedMaterials)
        {
            if (material == null || material.shader == null ||
                material.shader.name == "Hidden/InternalErrorShader")
                throw new InvalidOperationException("The imported model has a missing material or shader.");
        }

        var pipeline = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(
            "Assets/Settings/Mobile_RPAsset.asset");
        if (pipeline == null)
            throw new InvalidOperationException("The URP template pipeline asset failed to load.");
        if (!File.Exists("Packages/packages-lock.json"))
            throw new InvalidOperationException("Unity has not generated packages-lock.json.");

        Debug.Log($"DEPENDENCY_CHECK_PASS editor={Application.unityVersion} " +
                  $"iOSSupport=true urp=17.3.0 glTFast=6.16.1 renderers={renderers.Length}. " +
                  "This checks import and compilation, not device rendering or app functionality.");
    }

    private static void RequirePackage(string name, string version)
    {
        var package = UnityEditor.PackageManager.PackageInfo.GetAllRegisteredPackages()
            .FirstOrDefault(p => p.name == name);
        if (package == null || package.version != version)
            throw new InvalidOperationException($"Expected {name}@{version}.");
    }
}
