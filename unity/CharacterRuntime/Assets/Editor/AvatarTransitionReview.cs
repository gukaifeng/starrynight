using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

// Evaluate the shipped controller, not a reconstructed approximation. Reports stay
// local because per-frame morph and bone samples belong to the private avatar.
public static class AvatarTransitionReview
{
    public static void ValidateAll() { Run(); ValidateRoster(); }
    [Serializable] sealed class Frame
    {
        public int index;
        public float maxMorphDelta, maxBoneDegrees, eyeJoy, eyeAngry, cheek, cheekFX;
        public string morph, bone;
        public double animatorMilliseconds;
    }
    [Serializable] sealed class Sample
    {
        public string id;
        public int hz;
        public float left, right;
        public List<Frame> frames = new List<Frame>();
    }
    [Serializable] sealed class Report
    {
        public string scope = "Editor manual Animator evaluation; not device FPS or full player frame timing";
        public List<Sample> cases = new List<Sample>();
    }
    public static void Run()
    {
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var prefab = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Resources/Characters/anime-ichigo.prefab");
        if (!prefab) throw new Exception("TRANSITION_REVIEW_PREFAB_MISSING");
        var root = UnityEngine.Object.Instantiate(prefab);
        root.SetActive(true);
        try
        {
            if (Environment.GetEnvironmentVariable("STARRY_TRANSITION_REBUILD") == "1")
            {
                foreach (var old in root.GetComponentsInChildren<Animator>(true)) UnityEngine.Object.DestroyImmediate(old);
                UnityEngine.Object.DestroyImmediate(root.GetComponent<AvatarControlDriver>());
                string folder = "Assets/CharacterPackages/Imported/anime-ichigo";
                var idle = AssetDatabase.LoadAllAssetsAtPath(folder + "/model.glb").OfType<AnimationClip>().First(c => c.name == "Idle");
                idle.SampleAnimation(root, 0);
                PortableAvatarControllerBuilder.Prepare(root, folder, idle);
                AssetDatabase.SaveAssets();
            }
            foreach (var behavior in root.GetComponentsInChildren<MonoBehaviour>(true)) behavior.enabled = false;
            var driver = root.GetComponent<AvatarControlDriver>();
            if (!driver || !driver.Available) throw new Exception("TRANSITION_REVIEW_CONTROLLER_MISSING");
            driver.animator.gameObject.SetActive(true);
            driver.animator.enabled = true;
            foreach (var player in root.GetComponentsInChildren<Animation>(true)) player.enabled = false;
            var performance = root.AddComponent<CharacterPerformanceDriver>();
            performance.Bind(root.GetComponent<ViewerCharacter>());
            var skins = root.GetComponentsInChildren<SkinnedMeshRenderer>(true).Where(s => s.sharedMesh).ToArray();
            var shapes = skins.SelectMany(s => Enumerable.Range(0, s.sharedMesh.blendShapeCount)
                .Select(i => (skin: s, index: i, name: s.name + "/" + s.sharedMesh.GetBlendShapeName(i)))).ToArray();
            var bones = root.GetComponentsInChildren<Transform>(true);
            var report = new Report();
            void Set(string parameter, float value) { driver.Set(parameter, value); }
            foreach (int hz in new[] { 60, 120 })
            {
                void Probe(string id, Action prepare, Action change)
                {
                    driver.Reset();
                    for (int i = 0; i < hz; i++) {driver.AdvanceWeights(1f / hz);driver.animator.Update(1f / hz);}
                    prepare();
                    for (int i = 0; i < hz; i++) {driver.AdvanceWeights(1f / hz);driver.animator.Update(1f / hz);}
                    var weights = shapes.Select(s => s.skin.GetBlendShapeWeight(s.index)).ToArray();
                    var rotations = bones.Select(b => b.localRotation).ToArray();
                    var sample = new Sample { id = id, hz = hz };
                    report.cases.Add(sample);
                    change();
                    for (int i = 0; i < hz; i++)
                    {
                        var watch = System.Diagnostics.Stopwatch.StartNew();
                        driver.AdvanceWeights(1f / hz);
                        driver.animator.Update(1f / hz);
                        watch.Stop();
                        var frame = new Frame { index = i, animatorMilliseconds = watch.Elapsed.TotalMilliseconds };
                        for (int j = 0; j < shapes.Length; j++)
                        {
                            var s = shapes[j]; float current = s.skin.GetBlendShapeWeight(s.index);
                            float delta = Mathf.Abs(current - weights[j]);
                            if (delta > frame.maxMorphDelta) { frame.maxMorphDelta = delta; frame.morph = s.name; }
                            if (s.name == "Body/eye_joy_1") frame.eyeJoy = current;
                            if (s.name == "Body/eye_angry_2") frame.eyeAngry = current;
                            if (s.name == "Body/option_cheek_1") frame.cheek = current;
                            if (s.name == "Body/option_cheek_3") frame.cheekFX = current;
                            weights[j] = current;
                        }
                        for (int j = 0; j < bones.Length; j++)
                        {
                            float delta = Quaternion.Angle(rotations[j], bones[j].localRotation);
                            if (delta > frame.maxBoneDegrees) { frame.maxBoneDegrees = delta; frame.bone = bones[j].name; }
                            rotations[j] = bones[j].localRotation;
                        }
                        sample.frames.Add(frame);
                    }
                    sample.left = driver.Get("GestureLeft"); sample.right = driver.Get("GestureRight");
                }
                Probe("neutral-to-smile", () => {}, () => Set("GestureRight", 2));
                Probe("smile-to-pout", () => Set("GestureRight", 2), () => Set("GestureRight", 6));
                Probe("smile-to-group-reset", () => Set("GestureRight", 2), () => driver.Reset("原作手势",false));
                Probe("smile-to-full-reset", () => Set("GestureRight", 2), () => driver.Reset("",false));
                Probe("right-smile-to-left-sad", () => Set("GestureRight", 2), () => Set("GestureLeft", 3));
                string group=root.GetComponent<ViewerCharacter>().Manifest.performance.options.First(o=>o.id=="gesture-left-3").group;
                Probe("atomic-right-smile-to-left-sad", () => Set("GestureRight", 2), () => performance.Replace(group,new[]{"gesture-left-3"}));
                Probe("restore-user-smile", () => Set("GestureRight", 6), () => performance.Replace(group,new[]{"gesture-right-2","gesture-left-0"}));
                Probe("cheek-on", () => {}, () => Set("Face/Cheek", 1));
                Probe("cheek-off", () => Set("Face/Cheek", 1), () => driver.Reset("Facials",false));
            }
            string path = Environment.GetEnvironmentVariable("STARRY_TRANSITION_REPORT") ??
                Path.Combine(CharacterPackageBuilder.Root, ".local/checks/ichigo-transitions.json");
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, JsonUtility.ToJson(report, true) + "\n");
            if (Environment.GetEnvironmentVariable("STARRY_TRANSITION_ASSERT") == "1")
            {
                foreach(var sample in report.cases.Where(c=>c.id!="right-smile-to-left-sad"))
                {
                    // A one-frame morph jump or finger snap is a failed blend,
                    // even if the final parameter selections look correct.
                    if(sample.frames.Max(f=>f.maxMorphDelta)>.15f*60/sample.hz ||
                       sample.frames.Max(f=>f.maxBoneDegrees)>9f*60/sample.hz)
                        throw new Exception("TRANSITION_DISCONTINUITY: "+sample.id+"/"+sample.hz);
                    if(sample.id.Contains("reset") && (sample.frames.Last().eyeJoy>.001f || sample.frames.Last().cheekFX>.001f))
                        throw new Exception("TRANSITION_DEFAULT_RESIDUE: "+sample.id);
                    if(sample.id=="atomic-right-smile-to-left-sad" && (sample.right!=0 || sample.left!=3 || sample.frames.Last().eyeJoy>.001f))
                        throw new Exception("TRANSITION_PREVIOUS_CUE_STILL_ACTIVE");
                    if(sample.id=="restore-user-smile" && sample.frames.Last().eyeJoy<.999f)
                        throw new Exception("TRANSITION_USER_SELECTION_LOST");
                }
            }
            Debug.Log("AVATAR_TRANSITION_REVIEW_DONE cases=" + report.cases.Count + " path=" + path);
        }
        finally { UnityEngine.Object.DestroyImmediate(root); }
    }
    public static void ValidateRoster()
    {
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        int roles=0,options=0;
        foreach(string id in CharacterPackageBuilder.Roster.characters)
        {
            var prefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Resources/Characters/"+id+".prefab");
            var root=UnityEngine.Object.Instantiate(prefab);root.SetActive(true);
            try
            {
                var avatar=root.GetComponent<AvatarControlDriver>();
                if(!avatar)continue; // The two legacy author-animation adapters are unchanged.
                roles++;
                foreach(var behavior in root.GetComponentsInChildren<MonoBehaviour>(true))behavior.enabled=false;
                avatar.animator.enabled=true;
                foreach(var player in root.GetComponentsInChildren<Animation>(true))player.enabled=false;
                var character=root.GetComponent<ViewerCharacter>();
                var performance=root.AddComponent<CharacterPerformanceDriver>();performance.Bind(character);
                void Tick(){for(int frame=0;frame<75;frame++){avatar.AdvanceWeights(1f/60);avatar.animator.Update(1f/60);}}
                avatar.Reset();Tick();
                foreach(var option in character.Manifest.performance.options.Where(o=>o.ai?.automatic==true && !string.IsNullOrEmpty(o.control?.id)))
                {
                    var baseline=performance.Selections.Where(selected=>character.Manifest.performance.options.Any(o=>o.id==selected && o.group==option.group)).ToArray();
                    if(performance.Replace(option.group,new[]{option.id})!=null)throw new Exception("ATOMIC_CUE_REJECTED: "+id+"/"+option.id);
                    // Test the transaction before native state behaviors are allowed to update parameters.
                    if(!performance.Selections.Contains(option.id))throw new Exception("ATOMIC_CUE_NOT_SELECTED: "+id+"/"+option.id);
                    string[] selectedBefore=performance.Selections;
                    if(performance.Replace(option.group,new[]{"not-an-option"})==null || !selectedBefore.SequenceEqual(performance.Selections))throw new Exception("ATOMIC_INVALID_REQUEST_MUTATED_STATE");
                    Tick();
                    foreach(var skin in root.GetComponentsInChildren<SkinnedMeshRenderer>(true))
                        for(int i=0;i<skin.sharedMesh.blendShapeCount;i++)
                            if(!float.IsFinite(skin.GetBlendShapeWeight(i)))throw new Exception("ATOMIC_CUE_NONFINITE_MORPH: "+id);
                    if(performance.Replace(option.group,baseline)!=null)throw new Exception("ATOMIC_RESTORE_REJECTED: "+id);
                    foreach(var selected in baseline)if(!performance.Selections.Contains(selected))throw new Exception("ATOMIC_RESTORE_LOST_SELECTION: "+id+"/"+selected);
                    Tick();options++;
                }
            }
            finally{UnityEngine.Object.DestroyImmediate(root);}
        }
        if(roles<9 || options<50)throw new Exception("ATOMIC_ROSTER_COVERAGE_MISSING");
        Debug.Log("AVATAR_ATOMIC_ROSTER_PASS roles="+roles+" options="+options);
    }
    public static void ValidateLegacy()
    {
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);
        int roles=0,options=0;
        foreach(string id in CharacterPackageBuilder.Roster.characters)
        {
            var prefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Resources/Characters/"+id+".prefab");
            if(prefab.GetComponent<AvatarControlDriver>())continue;
            var root=UnityEngine.Object.Instantiate(prefab);root.SetActive(true);
            try
            {
                roles++;
                foreach(var behavior in root.GetComponentsInChildren<MonoBehaviour>(true))behavior.enabled=false;
                var character=root.GetComponent<ViewerCharacter>();
                var player=root.GetComponentInChildren<Animation>(true);player.enabled=true;player.Play("Idle");
                var performance=root.AddComponent<CharacterPerformanceDriver>();performance.Bind(character);
                void Tick(){for(int frame=0;frame<75;frame++){
                    performance.RestoreMorphs();performance.Step(1f/60);
                    foreach(AnimationState state in player)if(state.enabled)state.time+=1f/60*state.speed;
                    player.Sample();performance.ApplyFrame();
                }}
                Tick();
                // Legacy AI hints are generated in the host catalogue, not in
                // these two original manifests. Exercise every author option.
                foreach(var option in character.Manifest.performance.options)
                {
                    var baseline=performance.Selections.Where(selected=>character.Manifest.performance.options.Any(o=>o.id==selected && o.group==option.group)).ToArray();
                    if(performance.Replace(option.group,new[]{option.id})!=null || !performance.Selections.Contains(option.id))throw new Exception("LEGACY_ATOMIC_SELECT_FAILED: "+id+"/"+option.id);
                    Tick();
                    if(performance.Replace(option.group,baseline)!=null)throw new Exception("LEGACY_ATOMIC_RESTORE_REJECTED");
                    foreach(string selected in baseline)if(!performance.Selections.Contains(selected))throw new Exception("LEGACY_ATOMIC_RESTORE_LOST_SELECTION");
                    Tick();options++;
                }
            }
            finally{UnityEngine.Object.DestroyImmediate(root);}
        }
        if(roles!=2 || options<130)throw new Exception("LEGACY_ATOMIC_COVERAGE_MISSING roles="+roles+" options="+options);
        Debug.Log("AVATAR_ATOMIC_LEGACY_PASS roles="+roles+" options="+options);
    }
}
