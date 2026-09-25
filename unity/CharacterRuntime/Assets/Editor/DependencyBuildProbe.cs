using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// Builds a disposable scene solely to validate the installed iOS toolchain.
// This is not the V0 scene or the native host's Unity export pipeline.
public static class DependencyBuildProbe
{
    public static void ExportIOS()
    {
        DependencyReadiness.Check();
        const string folder = "Assets/DependencyBuildProbeTemp";
        if (Directory.Exists(folder))
            throw new InvalidOperationException("A previous probe directory exists; inspect it before retrying.");

        var root = Path.GetFullPath(Path.Combine(Application.dataPath, "../../.."));
        var output = Path.Combine(root, ".local/build/ios-dependency-probe");
        var setup = EditorSceneManager.GetSceneManagerSetup();
        var oldOS = PlayerSettings.iOS.targetOSVersionString;
        var oldSDK = PlayerSettings.iOS.sdkVersion;
        var oldDevice = PlayerSettings.iOS.targetDevice;
        var oldId = PlayerSettings.GetApplicationIdentifier(NamedBuildTarget.iOS);
        var oldBackend = PlayerSettings.GetScriptingBackend(NamedBuildTarget.iOS);
        var oldPipeline = GraphicsSettings.defaultRenderPipeline;
        var oldQualityPipeline = QualitySettings.renderPipeline;
        try
        {
            PlayerSettings.iOS.targetOSVersionString = "17.0";
            PlayerSettings.iOS.sdkVersion = iOSSdkVersion.DeviceSDK;
            PlayerSettings.iOS.targetDevice = iOSTargetDevice.iPhoneAndiPad;
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, "com.example.dependency-probe");
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.iOS, ScriptingImplementation.IL2CPP);
            var pipeline = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(
                "Assets/Settings/Mobile_RPAsset.asset");
            GraphicsSettings.defaultRenderPipeline = pipeline;
            QualitySettings.renderPipeline = pipeline;

            AssetDatabase.CreateFolder("Assets", "DependencyBuildProbeTemp");
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(
                "Assets/ThirdParty/RobotExpressive/RobotExpressive.glb");
            var model = (GameObject)PrefabUtility.InstantiatePrefab(prefab, scene);
            foreach (var animator in model.GetComponentsInChildren<Animator>(true))
                animator.enabled = false;
            foreach (var animation in model.GetComponentsInChildren<Animation>(true))
                animation.enabled = false;
            var camera = new GameObject("Probe Camera").AddComponent<Camera>();
            camera.transform.position = new Vector3(0, 2, -8);
            camera.transform.LookAt(new Vector3(0, 2, 0));
            camera.gameObject.AddComponent<UniversalAdditionalCameraData>();
            var light = new GameObject("Probe Light").AddComponent<Light>();
            light.type = LightType.Directional;
            light.transform.rotation = Quaternion.Euler(45, -30, 0);
            var scenePath = folder + "/Probe.unity";
            if (!EditorSceneManager.SaveScene(scene, scenePath))
                throw new InvalidOperationException("Could not save the temporary probe scene.");
            var result = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { scenePath }, locationPathName = output,
                target = BuildTarget.iOS, options = BuildOptions.None
            });
            if (result.summary.result != BuildResult.Succeeded)
                throw new InvalidOperationException($"iOS export failed: {result.summary.result}, errors={result.summary.totalErrors}.");
            Debug.Log($"DEPENDENCY_IOS_EXPORT_PASS editor={Application.unityVersion} " +
                      $"target=iOS backend=IL2CPP minimumOS=17.0 deviceFamily=1,2 " +
                      $"errors={result.summary.totalErrors} warnings={result.summary.totalWarnings}. Device run NOT_TESTED.");
        }
        finally
        {
            PlayerSettings.iOS.targetOSVersionString = oldOS;
            PlayerSettings.iOS.sdkVersion = oldSDK;
            PlayerSettings.iOS.targetDevice = oldDevice;
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, oldId);
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.iOS, oldBackend);
            GraphicsSettings.defaultRenderPipeline = oldPipeline;
            QualitySettings.renderPipeline = oldQualityPipeline;
            // Batch mode may start with no loaded scene, which Unity cannot
            // restore via RestoreSceneManagerSetup. Close the probe explicitly.
            if (setup.Any(s => s.isLoaded && s.isActive))
                EditorSceneManager.RestoreSceneManagerSetup(setup);
            else
                EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            AssetDatabase.DeleteAsset(folder);
            AssetDatabase.SaveAssets();
        }
    }
}
