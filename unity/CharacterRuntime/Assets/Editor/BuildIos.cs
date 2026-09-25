using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.iOS.Xcode;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public static class BuildIos
{
    const string ScenePath = "Assets/Scenes/ViewerScene.unity";
    static string Root => Path.GetFullPath(Path.Combine(Application.dataPath, "../../.."));

    [MenuItem("Model Space/Set up viewer")]
    public static void Setup()
    {
        Directory.CreateDirectory("Assets/Prefabs");
        Directory.CreateDirectory("Assets/Materials");
        AssetDatabase.Refresh();
        var pipeline = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>("Assets/Settings/Mobile_RPAsset.asset");
        if (!pipeline) throw new Exception("Mobile URP asset missing");
        pipeline.renderScale = 1f; pipeline.msaaSampleCount = 4;
        pipeline.shadowDistance = 45; pipeline.supportsHDR = false;
        GraphicsSettings.defaultRenderPipeline = pipeline;
        for (int i = 0; i < QualitySettings.names.Length; i++)
        { QualitySettings.SetQualityLevel(i); QualitySettings.renderPipeline = pipeline; }
        PlayerSettings.companyName = "Model Space";
        PlayerSettings.productName = "模型空间";
        PlayerSettings.colorSpace = ColorSpace.Linear;
        PlayerSettings.iOS.targetOSVersionString = "17.0";
        PlayerSettings.iOS.targetDevice = iOSTargetDevice.iPhoneAndiPad;
        PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
        PlayerSettings.allowedAutorotateToPortrait = true;
        PlayerSettings.allowedAutorotateToPortraitUpsideDown = true;
        PlayerSettings.allowedAutorotateToLandscapeLeft = true;
        PlayerSettings.allowedAutorotateToLandscapeRight = true;
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, "com.modelspace.viewer.runtime");
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.iOS, ScriptingImplementation.IL2CPP);
        PlayerSettings.SetManagedStrippingLevel(NamedBuildTarget.iOS, ManagedStrippingLevel.Minimal);
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var source = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/ThirdParty/RobotExpressive/RobotExpressive.glb");
        if (!source) throw new Exception("RobotExpressive missing; cannot build viewer");
        var wrapper = new GameObject("DefaultCharacter");
        var model = (GameObject)PrefabUtility.InstantiatePrefab(source, wrapper.transform);
        foreach (var animator in model.GetComponentsInChildren<Animator>(true)) animator.enabled = false;
        foreach (var animation in model.GetComponentsInChildren<Animation>(true)) animation.enabled = false;
        var renderers = model.GetComponentsInChildren<Renderer>();
        Bounds bounds = renderers[0].bounds;
        foreach (var r in renderers) bounds.Encapsulate(r.bounds);
        wrapper.transform.position = new Vector3(-bounds.center.x, -bounds.min.y, -bounds.center.z);
        PrefabUtility.SaveAsPrefabAssetAndConnect(wrapper, "Assets/Prefabs/DefaultCharacter.prefab", InteractionMode.AutomatedAction);
        var camera = new GameObject("MainCamera").AddComponent<Camera>();
        camera.tag = "MainCamera"; camera.fieldOfView = 35; camera.nearClipPlane = .05f; camera.farClipPlane = 100;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(245/255f,247/255f,251/255f);
        camera.gameObject.AddComponent<UniversalAdditionalCameraData>().renderPostProcessing = false;
        var key = new GameObject("KeyLight").AddComponent<Light>();
        key.type = LightType.Directional; key.intensity = 2.1f;
        key.transform.rotation = Quaternion.Euler(42, -35, 0); key.shadows = LightShadows.Soft;
        var fill = new GameObject("FillLight").AddComponent<Light>();
        fill.type = LightType.Directional; fill.intensity = .65f;
        fill.color = new Color(.78f,.85f,1); fill.transform.rotation = Quaternion.Euler(20,145,0);
        RenderSettings.ambientMode = AmbientMode.Flat;
        RenderSettings.ambientLight = new Color(.70f,.74f,.82f);
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.name = "Ground"; ground.transform.localScale = Vector3.one * 20;
        UnityEngine.Object.DestroyImmediate(ground.GetComponent<Collider>());
        var material = AssetDatabase.LoadAssetAtPath<Material>("Assets/Materials/Ground.mat");
        if (!material)
        {
            material = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            AssetDatabase.CreateAsset(material, "Assets/Materials/Ground.mat");
        }
        material.SetColor("_BaseColor", new Color(.88f,.91f,.96f));
        material.SetFloat("_Smoothness", .05f);
        ground.GetComponent<Renderer>().sharedMaterial = material;
        var receiver = new GameObject("AppBridgeReceiver").AddComponent<ViewerController>();
        receiver.gameObject.AddComponent<CharacterActions>();
        receiver.model = wrapper.transform; receiver.viewCamera = camera;
        EditorSceneManager.SaveScene(scene, ScenePath);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        AssetDatabase.SaveAssets();
        Debug.Log("MODELSPACE_SETUP_PASS");
    }

    [MenuItem("Model Space/Export iOS Simulator")]
    public static void ExportSimulator() => Export(true);
    [MenuItem("Model Space/Export iOS Device")]
    public static void ExportDevice() => Export(false);

    [MenuItem("Model Space/Validate viewer")]
    public static void Validate()
    {
        var bounds = new Bounds(Vector3.zero,new Vector3(2,4,1));
        float portrait = OrbitMath.FitDistance(bounds,.46f,35);
        float landscape = OrbitMath.FitDistance(bounds,2.16f,35);
        if (!(portrait > 0 && landscape > 0 && portrait >= landscape)) throw new Exception("Aspect fit invalid");
        if (OrbitMath.ClampPitch(-500) != -8 || OrbitMath.ClampPitch(500) != 65) throw new Exception("Pitch limits invalid");
        if (OrbitMath.ClampDistance(-1,3,10) != 3 || OrbitMath.ClampDistance(1000,3,10) != 22) throw new Exception("Zoom limits invalid");
        EditorSceneManager.OpenScene(ScenePath);
        var viewers = UnityEngine.Object.FindObjectsByType<ViewerController>(FindObjectsSortMode.None);
        if (viewers.Length != 1 || viewers[0].name != "AppBridgeReceiver") throw new Exception("Scene receiver invalid");
        if (!viewers[0].model || !viewers[0].viewCamera) throw new Exception("Scene references missing");
        var renderers = viewers[0].model.GetComponentsInChildren<Renderer>();
        if (renderers.Length == 0 || renderers.Any(r=>r.sharedMaterials.Any(m=>!m || !m.shader))) throw new Exception("Model/material invalid");
        if (viewers[0].model.GetComponentsInChildren<Animator>().Any(a=>a.enabled) || viewers[0].model.GetComponentsInChildren<Animation>().Any(a=>a.enabled)) throw new Exception("Automatic animation enabled");
        if (!viewers[0].GetComponent<CharacterActions>()) throw new Exception("Action controller missing");
        var animation = viewers[0].model.GetComponentInChildren<Animation>();
        foreach (string clip in new[] { "Idle", "Wave", "Jump", "Dance", "No" })
            if (!animation || !animation.GetClip(clip)) throw new Exception("Action missing: " + clip);
        Debug.Log("MODELSPACE_VALIDATION_PASS cameraLimits=PASS viewportFit=PASS scene=PASS model=PASS actions=PASS");
    }
    static void Export(bool simulator)
    {
        Setup();
        Validate();
        PlayerSettings.iOS.sdkVersion = simulator ? iOSSdkVersion.SimulatorSDK : iOSSdkVersion.DeviceSDK;
        PlayerSettings.iOS.simulatorSdkArchitecture = AppleMobileArchitectureSimulator.ARM64;
        string output = Path.Combine(Root, "build", simulator ? "unity-simulator" : "unity-device");
        var result = BuildPipeline.BuildPlayer(new BuildPlayerOptions { scenes = new[] { ScenePath },
            locationPathName = output, target = BuildTarget.iOS, options = BuildOptions.None });
        if (result.summary.result != BuildResult.Succeeded) throw new Exception("Unity export failed: " + result.summary.result);
        Postprocess(output);
        Directory.CreateDirectory(Path.Combine(Root, ".local/checks"));
        File.WriteAllText(Path.Combine(Root, ".local/checks/unity-" + (simulator ? "simulator" : "device") + "-export.json"),
            "{\"status\":\"PASS\",\"editor\":\"" + Application.unityVersion + "\",\"sdk\":\"" +
            (simulator ? "iphonesimulator" : "iphoneos") + "\",\"errors\":" + result.summary.totalErrors + "}");
        Debug.Log("MODELSPACE_EXPORT_PASS " + output);
    }
    static void Postprocess(string output)
    {
        string path = PBXProject.GetPBXProjectPath(output);
        var project = new PBXProject(); project.ReadFromFile(path);
        string framework = project.GetUnityFrameworkTargetGuid();
        string main = project.GetUnityMainTargetGuid();
        string data = project.FindFileGuidByProjectPath("Data");
        project.RemoveFileFromBuild(main, data);
        project.AddFileToBuild(framework, data);
        project.SetBuildProperty(framework, "PRODUCT_BUNDLE_IDENTIFIER", "com.modelspace.viewer.unity");
        project.SetBuildProperty(framework, "IPHONEOS_DEPLOYMENT_TARGET", "17.0");
        project.SetBuildProperty(framework, "SKIP_INSTALL", "YES");
        project.SetBuildProperty(framework, "DEFINES_MODULE", "YES");
        project.SetBuildProperty(framework, "ENABLE_BITCODE", "NO");
        project.WriteToFile(path);
        File.WriteAllText(Path.Combine(output, "modelspace-export.json"),
            "{\"frameworkTarget\":\"" + framework + "\",\"dataBundleId\":\"com.modelspace.viewer.unity\"}");
    }

    // Invoked with a graphics-capable Editor. Output is a real render of the shipped model.
    [MenuItem("Model Space/Render thumbnail")]
    public static void Thumbnail()
    {
        EditorSceneManager.OpenScene(ScenePath);
        var viewer = UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var camera = viewer.viewCamera;
        var renderers = viewer.model.GetComponentsInChildren<Renderer>();
        var bounds = renderers[0].bounds;
        foreach (var r in renderers) bounds.Encapsulate(r.bounds);
        camera.aspect = 1;
        float d = OrbitMath.FitDistance(bounds, 1, camera.fieldOfView) * .86f;
        camera.transform.position = bounds.center + Quaternion.Euler(12, OrbitMath.DefaultYaw, 0) * Vector3.back * d;
        camera.transform.LookAt(bounds.center);
        var rt = new RenderTexture(1200,1200,24,RenderTextureFormat.ARGB32);
        rt.Create(); camera.targetTexture = rt;
        RenderPipeline.SubmitRenderRequest(camera, new UniversalRenderPipeline.SingleCameraRequest { destination = rt });
        var previous = RenderTexture.active; RenderTexture.active = rt;
        var texture = new Texture2D(1200,1200,TextureFormat.RGB24,false);
        texture.ReadPixels(new Rect(0,0,1200,1200),0,0); texture.Apply();
        string directory = Path.Combine(Root,"ios/CharacterHost/Resources/Assets.xcassets/RobotThumbnail.imageset"); Directory.CreateDirectory(directory);
        File.WriteAllBytes(Path.Combine(directory,"RobotThumbnail.png"),texture.EncodeToPNG());
        RenderTexture.active = previous; camera.targetTexture = null;
        UnityEngine.Object.DestroyImmediate(texture); rt.Release(); UnityEngine.Object.DestroyImmediate(rt);
        Debug.Log("MODELSPACE_THUMBNAIL_PASS");
    }
}
