using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
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
    static string AtmosphereHash {
        get {using(var sha=SHA256.Create()) return string.Concat(sha.ComputeHash(File.ReadAllBytes(Path.Combine(Application.dataPath,"Resources/CharacterAtmospheres.json"))).Select(b=>b.ToString("x2")));}
    }

    [MenuItem("Model Space/Set up viewer")]
    public static void Setup()
    {
        if (EditorUtility.scriptCompilationFailed) throw new Exception("Cannot generate a scene while C# compilation has errors");
        CharacterPackageBuilder.Preflight();
        CharacterPaletteBuilder.Prepare();
        EnvironmentPackageBuilder.Preflight();
        Directory.CreateDirectory("Assets/Prefabs");
        Directory.CreateDirectory("Assets/Materials");
        AssetDatabase.Refresh();
        var pipeline = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>("Assets/Settings/Mobile_RPAsset.asset");
        if (!pipeline) throw new Exception("Mobile URP asset missing");
        pipeline.renderScale = 1f; pipeline.msaaSampleCount = 4;
        // Covers the bounded conversation and full-action framing distances.
        pipeline.shadowDistance = 50; pipeline.supportsHDR = true;
        pipeline.mainLightShadowmapResolution = 4096;
        pipeline.shadowCascadeCount = 2; pipeline.cascade2Split = .45f;
        var pipelineSettings = new SerializedObject(pipeline);
        pipelineSettings.FindProperty("m_SoftShadowsSupported").boolValue = true;
        pipelineSettings.FindProperty("m_SoftShadowQuality").intValue = (int)SoftShadowQuality.High;
        pipelineSettings.ApplyModifiedPropertiesWithoutUndo();
        pipeline.supportsCameraOpaqueTexture = false;
        pipeline.supportsCameraDepthTexture = false;
        pipeline.useSRPBatcher = true;
        EditorUtility.SetDirty(pipeline);
        GraphicsSettings.defaultRenderPipeline = pipeline;
        for (int i = 0; i < QualitySettings.names.Length; i++)
        { QualitySettings.SetQualityLevel(i); QualitySettings.renderPipeline = pipeline; }
        PlayerSettings.companyName = "Model Space";
        PlayerSettings.productName = "模型空间";
        PlayerSettings.colorSpace = ColorSpace.Linear;
        PlayerSettings.iOS.targetOSVersionString = "17.0";
        PlayerSettings.iOS.targetDevice = iOSTargetDevice.iPhoneAndiPad;
        var appleSettings = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset")[0]);
        appleSettings.FindProperty("appleEnableProMotion").boolValue = true;
        appleSettings.ApplyModifiedPropertiesWithoutUndo();
        PlayerSettings.enableFrameTimingStats = true;
        PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
        PlayerSettings.allowedAutorotateToPortrait = true;
        PlayerSettings.allowedAutorotateToPortraitUpsideDown = true;
        PlayerSettings.allowedAutorotateToLandscapeLeft = true;
        PlayerSettings.allowedAutorotateToLandscapeRight = true;
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, "com.modelspace.viewer.runtime");
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.iOS, ScriptingImplementation.IL2CPP);
        PlayerSettings.SetManagedStrippingLevel(NamedBuildTarget.iOS, ManagedStrippingLevel.Minimal);
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var camera = new GameObject("MainCamera").AddComponent<Camera>();
        camera.tag = "MainCamera"; camera.fieldOfView = 35; camera.nearClipPlane = .05f; camera.farClipPlane = 100;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(.60f,.69f,.75f);
        camera.allowHDR = true; camera.allowMSAA = true;
        var cameraData = camera.gameObject.AddComponent<UniversalAdditionalCameraData>();
        cameraData.renderPostProcessing = true; cameraData.dithering = true;
        var volume = new GameObject("StudioToneMapping").AddComponent<Volume>(); volume.isGlobal = true;
        var profile = AssetDatabase.LoadAssetAtPath<VolumeProfile>("Assets/StudioRobot/StudioVolume.asset");
        if (!profile) { profile = ScriptableObject.CreateInstance<VolumeProfile>(); AssetDatabase.CreateAsset(profile,"Assets/StudioRobot/StudioVolume.asset"); }
        if (!profile.TryGet<Tonemapping>(out var tone)) { tone = profile.Add<Tonemapping>(true); AssetDatabase.AddObjectToAsset(tone,profile); }
        tone.mode.Override(TonemappingMode.ACES); EditorUtility.SetDirty(profile); volume.sharedProfile = profile;
        var key = new GameObject("KeyLight").AddComponent<Light>();
        key.type = LightType.Directional; key.intensity = 1.6f; key.color = new Color(1,.94f,.85f);
        key.transform.rotation = Quaternion.Euler(50, 145, 0); key.shadows = LightShadows.Soft;
        key.shadowBias = .035f; key.shadowNormalBias = .18f; key.shadowStrength = .85f;
        var lightData = key.gameObject.AddComponent<UniversalAdditionalLightData>();
        lightData.usePipelineSettings = false; lightData.softShadowQuality = SoftShadowQuality.High;
        var fill = new GameObject("FillLight").AddComponent<Light>();
        fill.type = LightType.Directional; fill.intensity = .35f;
        fill.color = new Color(.78f,.85f,1); fill.transform.rotation = Quaternion.Euler(20,-115,0);
        var rim = new GameObject("RimLight").AddComponent<Light>(); rim.type = LightType.Directional;
        rim.intensity = .8f; rim.color = new Color(.78f,.88f,1); rim.transform.rotation = Quaternion.Euler(35,-20,0);
        RenderSettings.ambientMode = AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = new Color(.48f,.50f,.53f);
        RenderSettings.ambientEquatorColor = new Color(.27f,.29f,.31f);
        RenderSettings.ambientGroundColor = new Color(.10f,.12f,.15f);
        RenderSettings.defaultReflectionMode = DefaultReflectionMode.Custom;
        RenderSettings.customReflectionTexture = StudioRobotBuilder.StudioReflection();
        RenderSettings.reflectionIntensity = 1;
        RenderSettings.fog = true; RenderSettings.fogMode = FogMode.ExponentialSquared;
        RenderSettings.fogColor = camera.backgroundColor; RenderSettings.fogDensity = .014f;
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.name = "Ground"; ground.transform.localScale = Vector3.one * 20;
        UnityEngine.Object.DestroyImmediate(ground.GetComponent<Collider>());
        var material = AssetDatabase.LoadAssetAtPath<Material>("Assets/Materials/Ground.mat");
        if (!material)
        {
            material = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            AssetDatabase.CreateAsset(material, "Assets/Materials/Ground.mat");
        }
        material.SetColor("_BaseColor", new Color(.35f,.43f,.48f));
        material.SetFloat("_Smoothness", .18f); EditorUtility.SetDirty(material);
        ground.GetComponent<Renderer>().sharedMaterial = material;
        var receiver = new GameObject("AppBridgeReceiver").AddComponent<ViewerController>();
        receiver.gameObject.AddComponent<CharacterActions>();
        receiver.gameObject.AddComponent<RenderPerformance>();
        var studio = receiver.gameObject.AddComponent<CharacterStudioDriver>();
        CharacterRoomBuilder.Create(studio,key,fill,rim,ground.GetComponent<Renderer>());
        EnvironmentPackageBuilder.Create(studio,camera);
        // The bundled first companion is ready on the first rendered scene frame.
        receiver.characters = CharacterPackageBuilder.CreateImported().ToArray();
        var initial = receiver.characters.Single(c=>c.modelId==CharacterPackageBuilder.Roster.defaultCharacter);
        initial.gameObject.SetActive(true);
        receiver.model = initial.transform; receiver.viewCamera = camera;
        CharacterResourceBuilder.Prepare(receiver);
        CharacterPackageBuilder.PrepareEffects();
        CharacterPackageBuilder.CatalogForHost(receiver.characters);
        EditorSceneManager.SaveScene(scene, ScenePath);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
        AssetDatabase.SaveAssets();
        Debug.Log("MODELSPACE_SETUP_PASS");
    }

    [MenuItem("Model Space/Export iOS Simulator")]
    public static void ExportSimulator() => Export(true);
    [MenuItem("Model Space/Export iOS Device")]
    public static void ExportDevice() => Export(false);
    // Recovery path after Setup/thumbnail generation succeeded but the Editor's
    // Metal shader reload crashed. The saved scene is still validated; render it
    // in the App after a graphics-free export, never regenerate thumbnails there.
    public static void ExportPreparedSimulator() => Export(true,true);
    public static void ExportPreparedDevice() => Export(false,true);
    // Headless exports isolate scene/thumbnail rendering from the subsequent
    // URP build callback initialization. Both phases still validate the scene.
    public static void PrepareExport() {
        Setup();Validate();
        CharacterModelAutonomyReview.Validate(UnityEngine.Object.FindFirstObjectByType<ViewerController>());
        Thumbnail();
    }

    [MenuItem("Model Space/Validate viewer")]
    public static void Validate()
    {
        var bounds = new Bounds(Vector3.zero,new Vector3(2,4,1));
        float portrait = OrbitMath.FitDistance(bounds,.46f,35);
        float landscape = OrbitMath.FitDistance(bounds,2.16f,35);
        if (!(portrait > 0 && landscape > 0 && portrait >= landscape)) throw new Exception("Aspect fit invalid");
        FramingReview.Validate();
        FramingMotionReview.Validate();
        EditorSceneManager.OpenScene(ScenePath);
        var viewers = UnityEngine.Object.FindObjectsByType<ViewerController>(FindObjectsSortMode.None);
        if (viewers.Length != 1 || viewers[0].name != "AppBridgeReceiver") throw new Exception("Scene receiver invalid");
        if (!viewers[0].model || !viewers[0].viewCamera) throw new Exception("Scene references missing");
        if (viewers[0].characters == null || viewers[0].characters.Length != CharacterPackageBuilder.Roster.characters.Length ||
            viewers[0].characters.Select(c=>c.modelId).Distinct().Count() != viewers[0].characters.Length)
            throw new Exception("Character catalog has missing or duplicate entries");
        foreach (var character in viewers[0].characters)
        {
            character.ApplyContract(); CharacterPackageBuilder.ValidateBindings(character);
            // Explicitly validate authored performances in every export, including the
            // prepared-scene recovery path which deliberately does not run Setup again.
            CharacterPerformanceBuilder.Validate(character);
            var player = character.GetComponentInChildren<Animation>(true);
            if (!player || player.enabled || !player.GetClip("Idle")) throw new Exception("Character animation invalid: " + character.modelId);
            foreach (string action in character.actions)
                if (!player.GetClip(action)) throw new Exception("Character clip missing: " + character.modelId + "/" + action);
            foreach (string action in new[] { "Idle" }.Concat(character.actions).Concat(character.Manifest.posture?.Clips ?? System.Array.Empty<string>())
                .Concat(character.Manifest.performance?.Clips ?? System.Array.Empty<string>()).Distinct())
            {
                var clip = player.GetClip(action);
                foreach (var binding in AnimationUtility.GetCurveBindings(clip))
                {
                    if (!character.transform.Find(binding.path)) throw new Exception("Animation path missing: " + binding.path);
                    var curve = AnimationUtility.GetEditorCurve(clip,binding);
                    for (int sample = 0; sample <= 120; sample++)
                    {
                        float value = curve.Evaluate(clip.length*sample/120);
                        if (float.IsNaN(value) || float.IsInfinity(value)) throw new Exception("Invalid animation curve: " + action);
                    }
                }
            }
            foreach (var skin in character.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                if (skin.bones.Length != skin.sharedMesh.bindposes.Length || skin.bones.Any(b=>!b))
                    throw new Exception("Invalid skin bindings: " + character.modelId);
                foreach (var weight in skin.sharedMesh.boneWeights)
                    if (Mathf.Abs(weight.weight0+weight.weight1+weight.weight2+weight.weight3-1)>.0001f ||
                        weight.boneIndex0<0 || weight.boneIndex0>=skin.bones.Length || weight.boneIndex1<0 || weight.boneIndex1>=skin.bones.Length)
                        throw new Exception("Invalid skin weights: " + character.modelId);
                foreach (var vertex in skin.sharedMesh.vertices)
                    if (float.IsNaN(vertex.sqrMagnitude)||float.IsInfinity(vertex.sqrMagnitude)) throw new Exception("Invalid character vertex");
            }
            if (character.GetComponentsInChildren<Renderer>(true).Any(r=>r.sharedMaterials.Any(m=>!m || !m.shader)))
                throw new Exception("Character material invalid: " + character.modelId);
            // Source avatars include intentionally small bodies. Portrait
            // calibration uses each body's measured bounds, not a 1 m minimum.
            var restSize=character.RestBounds().size;
            if (!float.IsFinite(restSize.sqrMagnitude) || restSize.y<.05f || restSize.y>20f || restSize.x<=0 || restSize.z<=0)
                throw new Exception("Character bounds invalid: "+character.modelId+" "+restSize);
        }
        var renderers = viewers[0].model.GetComponentsInChildren<Renderer>();
        if (renderers.Length == 0 || renderers.Any(r=>r.sharedMaterials.Any(m=>!m || !m.shader))) throw new Exception("Model/material invalid");
        // Full portable companions own a reviewed Animator through this driver.
        // It is enabled intentionally; source Animators and legacy autoplay are
        // still forbidden. The old default cat did not exercise this branch.
        var control=viewers[0].model.GetComponent<AvatarControlDriver>();
        if (viewers[0].model.GetComponentsInChildren<Animator>().Any(a=>a.enabled && (!control || a!=control.animator)) ||
            viewers[0].model.GetComponentsInChildren<Animation>().Any(a=>a.enabled || a.playAutomatically))
            throw new Exception("Unowned automatic animation enabled");
        if (!viewers[0].GetComponent<CharacterActions>()) throw new Exception("Action controller missing");
        var appleSettings = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset")[0]);
        if (!appleSettings.FindProperty("appleEnableProMotion").boolValue) throw new Exception("ProMotion must be enabled");
        var animation = viewers[0].model.GetComponentInChildren<Animation>();
        foreach (string clip in new[] { "Idle" }.Concat(viewers[0].model.GetComponent<ViewerCharacter>().actions))
            if (!animation || !animation.GetClip(clip)) throw new Exception("Action missing: " + clip);
        Debug.Log("MODELSPACE_VALIDATION_PASS cameraLimits=PASS viewportFit=PASS scene=PASS model=PASS actions=PASS");
    }
    static void Export(bool simulator, bool prepared=false)
    {
        if(!prepared) Setup();
        Validate();
        if(!prepared) Thumbnail();
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
            "{\"frameworkTarget\":\"" + framework + "\",\"dataBundleId\":\"com.modelspace.viewer.unity\",\"characterDeliveryRevision\":1,\"emotionPerformanceRevision\":1,\"imageBackdropRevision\":1,\"imageBackdropCatalogSha256\":\""+AtmosphereHash+"\",\"contentVersion\":6,\"studioProtocol\":1,\"atmosphereRevision\":1,\"framingProtocol\":8,\"gazeRevision\":1,\"portraitRevision\":1,\"immersionRevision\":2,\"nativeGestureRevision\":2,\"autonomyRevision\":2,\"inspectionGestureRevision\":"+CharacterInspectionRotation.Revision+",\"companionProtocol\":1,\"environmentApi\":1,\"environmentCatalogSha256\":\""+EnvironmentPackageBuilder.CatalogHash+"\",\"characterApi\":1,\"catalogSha256\":\""+CharacterPackageBuilder.CatalogHash+"\",\"models\":["+string.Join(",",UnityEngine.Object.FindFirstObjectByType<ViewerController>().characters.Select(c=>"\""+c.modelId+"\""))+"]}");
    }

    // Invoked with a graphics-capable Editor. Output is a real render of the shipped model.
    [MenuItem("Model Space/Render thumbnail")]
    public static void Thumbnail()
    {
        EditorSceneManager.OpenScene(ScenePath);
        EnvironmentPackageBuilder.Thumbnails();
        var viewer = UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach (var character in viewer.characters)
        {
            foreach (var item in viewer.characters) item.gameObject.SetActive(item == character);
            RenderThumbnail(viewer, character);
        }
        // Do not persist thumbnail-only selection changes into the playable scene.
        EditorSceneManager.OpenScene(ScenePath);
        Debug.Log("MODELSPACE_THUMBNAILS_PASS");
    }
    public static void ThumbnailCharacter(string id,string room)
    {
        EditorSceneManager.OpenScene(ScenePath);
        try
        {
            var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
            var character=viewer.characters.Single(c=>c.modelId==id);
            foreach(var actor in viewer.characters)actor.gameObject.SetActive(actor==character);
            var studio=viewer.GetComponent<CharacterStudioDriver>();studio.Bind(character);
            studio.Configure(new StudioSettings {room=room},true);
            RenderThumbnail(viewer,character);
        }
        finally {EditorSceneManager.OpenScene(ScenePath);}
    }
    static void RenderThumbnail(ViewerController viewer, ViewerCharacter character)
    {
        var camera = viewer.viewCamera;
        var player = character.GetComponentInChildren<Animation>();
        if (player && player.GetClip("Idle")) player.GetClip("Idle").SampleAnimation(character.gameObject,0);
        var bounds = character.RestBounds();
        camera.aspect = 1;camera.rect=new Rect(0,0,1,1);
        float d = OrbitMath.FitDistance(bounds, 1, camera.fieldOfView) * .86f;
        camera.transform.position = bounds.center + Quaternion.Euler(12, OrbitMath.DefaultYaw, 0) * Vector3.back * d;
        camera.transform.LookAt(bounds.center);
        if (character.modelId == "real-woman")
        {
            var studio=viewer.GetComponent<CharacterStudioDriver>();studio.Bind(character);studio.Configure(new StudioSettings());
            RealCharacterReview.Portrait(camera,character);
        }
        string name = character.Manifest.display.thumbnail;
        string directory = Path.Combine(Root,"ios/StarryNight/Resources/Assets.xcassets/"+name+".imageset"); Directory.CreateDirectory(directory);
        CharacterPerformanceVisualProbe.RenderFrozenPose(character,camera,Path.Combine(directory,name+".png"),1200,1200);
        File.WriteAllText(Path.Combine(directory,"Contents.json"),"{\"images\":[{\"filename\":\""+name+".png\",\"idiom\":\"universal\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}");
        Debug.Log("MODELSPACE_THUMBNAIL_PASS");
    }
}

public static class FramingReview
{
    public static void BakeCharacter(ViewerCharacter character)
    {
        var player = character.GetComponentInChildren<Animation>(true);
        var envelopes = new System.Collections.Generic.List<FramingEnvelope>();
        var baked = new Mesh();
        try
        {
            foreach (string action in new[] { "Idle" }.Concat(character.actions).Concat(character.Manifest.posture?.Clips ?? System.Array.Empty<string>()).Distinct())
            {
                var clip = player.GetClip(action);
                var total = new Bounds(); bool first = true;
                int steps = Mathf.Max(1, Mathf.CeilToInt(clip.length * 30));
                if(character.Manifest.posture!=null && character.Manifest.posture.poses.Any(p=>p.parameters.Any(v=>v.lowClip==action || v.highClip==action))) steps=1;
                for (int step = 0; step <= steps; step++)
                {
                    clip.SampleAnimation(character.gameObject, clip.length * step / steps);
                    foreach (var renderer in character.GetComponentsInChildren<Renderer>(true))
                    {
                        if(!renderer.enabled || !renderer.gameObject.activeInHierarchy)continue;
                        Bounds local;
                        if (renderer is SkinnedMeshRenderer skin) { skin.BakeMesh(baked,true); baked.RecalculateBounds(); local = baked.bounds; }
                        else if (renderer.GetComponent<MeshFilter>() is MeshFilter filter && filter.sharedMesh) local = filter.sharedMesh.bounds;
                        else continue;
                        for (int corner = 0; corner < 8; corner++)
                        {
                            var point = character.transform.InverseTransformPoint(renderer.transform.TransformPoint(Corner(local, corner)));
                            if (first) { total = new Bounds(point, Vector3.zero); first = false; } else total.Encapsulate(point);
                        }
                    }
                }
                envelopes.Add(new FramingEnvelope { action = action, localBounds = total });
            }
            if(character.Manifest.posture!=null) foreach(var pose in character.Manifest.posture.poses)
            {
                var total=envelopes.First(e=>e.action==pose.clip).localBounds;
                foreach(string clip in pose.parameters.SelectMany(p=>new[]{p.lowClip,p.highClip}).Concat(pose.actions.Select(a=>a.clip)))
                    total.Encapsulate(envelopes.First(e=>e.action==clip).localBounds);
                total.Expand(.10f);
                foreach(string clip in new[]{pose.clip}.Concat(pose.actions.Select(a=>a.clip))) envelopes.First(e=>e.action==clip).localBounds=total;
            }
            character.framingEnvelopes = envelopes.ToArray();
        }
        finally { UnityEngine.Object.DestroyImmediate(baked); player.GetClip("Idle").SampleAnimation(character.gameObject,0); }
    }
    public static void Validate()
    {
        const string scene = "Assets/Scenes/ViewerScene.unity";
        if (FramingMath.Size(-3) != .9f || FramingMath.Size(8) != 1.1f || FramingMath.Size(float.NaN) != 1 ||
            FramingMath.Angle(-90) != -20 || FramingMath.Angle(90) != 20 || FramingMath.Angle(float.PositiveInfinity) != 0 ||
            FramingMath.Shot("orbit") != "conversation") throw new Exception("Framing boundary validation failed");
        EditorSceneManager.OpenScene(scene);
        int projections = 0, samples = 0;
        var viewer = UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var camera = viewer.viewCamera;
        try
        {
            foreach (var character in viewer.characters)
            {
                foreach (var other in viewer.characters) other.gameObject.SetActive(other == character);
                var player = character.GetComponentInChildren<Animation>(true);
                player.GetClip("Idle").SampleAnimation(character.gameObject, 0);
                var rest = character.RestBounds();
                Debug.Log("FRAMING_BOUNDS " + character.modelId + " " + rest);
                foreach (string shot in new[] { "conversation", "full" })
                foreach (float aspect in new[] { .3f, .45f, .7f, 1f, 1.7f, 3.4f, 6f })
                foreach (float size in new[] { .9f, 1f, 1.1f })
                foreach (float angle in new[] { -20f, 0f, 20f })
                {
                    var region = shot == "full" ? FramingMath.FullRegion(character.FramingBounds("Idle")) : FramingMath.Region(rest, shot, false);
                    SetCamera(camera, region, aspect, size, angle);
                    CheckBounds(camera, region, .045f, character.modelId + "/" + shot);
                    projections += 8;
                }
                // Independently sample the real shipped clips. Full action framing must
                // contain the animated mesh, while near shots intentionally crop the legs.
                var baked = new Mesh();
                try
                {
                    foreach (string clipName in new[] { "Idle" }.Concat(character.actions))
                    {
                        var clip = player.GetClip(clipName);
                        for (int phase = 0; phase <= 12; phase++)
                        {
                            clip.SampleAnimation(character.gameObject, clip.length * phase / 12f);
                            var all = new Bounds(); bool first = true;
                            foreach (var renderer in character.GetComponentsInChildren<Renderer>(true))
                            {
                                if(!renderer.enabled || !renderer.gameObject.activeInHierarchy)continue;
                                Bounds local;
                                if (renderer is SkinnedMeshRenderer skin) { skin.BakeMesh(baked,true); baked.RecalculateBounds(); local = baked.bounds; }
                                else if (renderer.GetComponent<MeshFilter>() is MeshFilter filter && filter.sharedMesh) local = filter.sharedMesh.bounds;
                                else continue;
                                for (int corner = 0; corner < 8; corner++)
                                {
                                    Vector3 point = renderer.transform.TransformPoint(Corner(local, corner));
                                    if (first) { all = new Bounds(point, Vector3.zero); first = false; } else all.Encapsulate(point);
                                }
                            }
                            foreach (float aspect in new[] { .45f, 1.7f, 6f })
                            foreach (float angle in new[] { -20f, 20f })
                            {
                                SetCamera(camera, FramingMath.FullRegion(character.FramingBounds(clipName)), aspect, 1.1f, angle);
                                CheckBounds(camera, all, .008f, character.modelId + "/" + clipName + "/" + phase);
                                projections += 8;
                            }
                            samples++;
                        }
                    }
                }
                finally { UnityEngine.Object.DestroyImmediate(baked); }
            }
            string directory = Path.GetFullPath(Path.Combine(Application.dataPath,"../../../docs/verification/framing"));
            Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory,"unity-projection.json"),
                "{\"status\":\"PASS\",\"boundaryValidation\":true,\"projectionPoints\":" + projections + ",\"animationSamples\":" + samples + ",\"models\":2,\"maxSize\":1.1,\"angleLimit\":20,\"aspectRange\":[0.3,6],\"scope\":\"rest regions and sampled baked animation bounds; secondary dynamics excluded\"}");
            Debug.Log("XUYU_FRAMING_PASS projections=" + projections + " animationSamples=" + samples);
        }
        finally { EditorSceneManager.OpenScene(scene); }
    }
    static void SetCamera(Camera camera, Bounds region, float aspect, float size, float angle)
    {
        camera.rect = new Rect(0,0,1,1); camera.aspect = aspect;
        var rotation = FramingMath.Rotation(angle);
        float distance = FramingMath.Distance(region,rotation,aspect,camera.fieldOfView,size,camera.nearClipPlane);
        camera.transform.SetPositionAndRotation(region.center - rotation * Vector3.forward * distance,rotation);
    }
    static Vector3 Corner(Bounds bounds, int corner) => bounds.center + Vector3.Scale(bounds.extents,
        new Vector3((corner & 1) == 0 ? -1 : 1,(corner & 2) == 0 ? -1 : 1,(corner & 4) == 0 ? -1 : 1));
    static void CheckBounds(Camera camera, Bounds bounds, float margin, string label)
    {
        for (int i = 0; i < 8; i++)
        {
            var point = camera.WorldToViewportPoint(Corner(bounds,i));
            if (point.z <= camera.nearClipPlane || point.x < margin || point.x > 1-margin || point.y < margin || point.y > 1-margin)
                throw new Exception("Framing projection outside safe region: " + label + " aspect=" + camera.aspect + " point=" + point);
        }
    }
}
