using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;
using ModelSpace;

public static class AvatarContinuityReview
{
    // Incremental runtime-only changes reuse the already connected scene and
    // reviewed framing/media. Refuse stale prefabs before either player export.
    public static void ExportSimulator(){ValidatePrepared();BuildIos.ExportPreparedSimulator();CharacterBundleBuilder.BuildSimulator();}
    public static void ExportDevice(){ValidatePrepared();BuildIos.ExportPreparedDevice();CharacterBundleBuilder.BuildDevice();}
    static void ValidatePrepared() {
        BuildIos.Validate();
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var character in viewer.characters) {
            var avatar=character.GetComponent<AvatarControlDriver>();var continuity=character.GetComponent<AvatarPoseContinuity>();var follow=character.GetComponent<AvatarArmFollow>();
            if(!avatar || !continuity || !follow || !continuity.enabled || !follow.enabled || avatar.continuity!=continuity || follow.joints.Length!=6 || continuity.bones.Length==0 || continuity.morphs.Length==0)
                throw new Exception("CONTINUITY_SAVED_SCENE_STALE "+character.modelId);
        }
        Debug.Log("CONTINUITY_SAVED_SCENE_PASS roles="+viewer.characters.Length);
    }
    [Serializable] public class Case {public string id,option,morph,bone;public int hz,maxFrame,boneFrame;public float firstMorphStep,maxMorphStep,maxAuthoredAnimatedStep,firstBoneStep,maxBoneStep,armOffset,armRestError;}
    [Serializable] class MotionList {public Motion[] motions;}
    [Serializable] class Motion {public Curve[] curves;}
    [Serializable] class Curve {public string path,property;public Key[] keys;}
    [Serializable] class Key {public float time,value;}
    [Serializable] public class Report {public string scope="Saved prefab CPU evaluation at 60/120 Hz; not measured device FPS";public List<Case> cases=new List<Case>();}
    public static void Run()
    {
        if(Environment.GetEnvironmentVariable("STARRY_SKIP_ARM_REVIEW")!="1")AvatarIdleArmReview.Run();
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);
        var report=new Report();
        foreach(string id in CharacterPackageBuilder.Roster.characters) {
            if(Environment.GetEnvironmentVariable("STARRY_CONTINUITY_ONLY") is string only && only!=id)continue;
            var prefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Prefabs/Package_"+id+".prefab");
            var root=UnityEngine.Object.Instantiate(prefab);root.SetActive(true);
            try {
                foreach(var b in root.GetComponentsInChildren<MonoBehaviour>(true))b.enabled=false;
                foreach(var p in root.GetComponentsInChildren<Animation>(true))p.enabled=false;
                var avatar=root.GetComponent<AvatarControlDriver>();var continuity=root.GetComponent<AvatarPoseContinuity>();
                var follow=root.GetComponent<AvatarArmFollow>();
                if(!avatar || !continuity || !follow || follow.joints.Length!=6)throw new Exception("CONTINUITY_COMPONENT_MISSING "+id);
                avatar.animator.enabled=true;
                if(avatar.animator.layerCount<1)throw new Exception("CONTINUITY_CONTROLLER_UNBOUND "+id);
                var character=root.GetComponent<ViewerCharacter>();
                var performance=root.AddComponent<CharacterPerformanceDriver>();performance.Bind(character);
                var bones=continuity.bones.Where(b=>b.target).Select(b=>b.target).ToArray();
                var shapes=continuity.morphs;
                // Preserve original blinking/pulsing decorative FX. Their
                // internal stepped keys are distinct from switching expressions.
                var source=JsonUtility.FromJson<MotionList>(CharacterMotionData.Read("Assets/CharacterPackages/Imported/"+id+"/avatar-motions.json"));
                var animated=new HashSet<string>(source.motions.SelectMany(m=>m.curves).Where(c=>c.property.StartsWith("blendShape.") && c.keys.Length>1 && c.keys.Max(k=>k.value)-c.keys.Min(k=>k.value)>.01f).Select(c=>c.path+"/"+c.property.Substring(11)));
                var animatedShapes=shapes.Select(m=>animated.Contains(AnimationUtility.CalculateTransformPath(m.skin.transform,avatar.animator.transform)+"/"+m.skin.sharedMesh.GetBlendShapeName(m.index))).ToArray();
                float[] Weights()=>shapes.Select(m=>m.skin.GetBlendShapeWeight(m.index)/Mathf.Max(.001f,CharacterContract.MorphScale(m.skin,m.index))).ToArray();
                void Tick(float dt){follow.Restore();continuity.Restore();avatar.AdvanceWeights(dt);avatar.animator.Update(dt);continuity.Apply(dt);}
                foreach(int hz in new[]{60,120}) {
                    float dt=1f/hz;
                    avatar.Reset();continuity.Reset();follow.Reset();
                    for(int i=0;i<hz;i++)Tick(dt);
                    foreach(var option in character.Manifest.performance.options.Where(o=>o.ai?.automatic==true && !string.IsNullOrEmpty(o.control?.id))) {
                        void Probe(string label,Action change) {
                            var row=new Case {id=id,option=label,hz=hz};report.cases.Add(row);
                            var previousWeights=Weights();var previousRotations=bones.Select(b=>b.localRotation).ToArray();
                            change();
                            for(int frame=0;frame<hz/2;frame++) {
                                Tick(dt);var current=Weights();float morph=0,bone=0;
                                float firstAll=0;
                                for(int i=0;i<current.Length;i++){if(!float.IsFinite(current[i]))throw new Exception("CONTINUITY_NONFINITE "+id);float changeSize=Mathf.Abs(current[i]-previousWeights[i]);firstAll=Mathf.Max(firstAll,changeSize);if(animatedShapes[i]){row.maxAuthoredAnimatedStep=Mathf.Max(row.maxAuthoredAnimatedStep,changeSize);continue;}if(changeSize>row.maxMorphStep){row.morph=shapes[i].skin.sharedMesh.GetBlendShapeName(shapes[i].index);row.maxFrame=frame;}morph=Mathf.Max(morph,changeSize);}
                                for(int i=0;i<bones.Length;i++){float angle=CharacterAutonomy.MotionAngle(previousRotations[i],bones[i].localRotation);if(!float.IsFinite(angle))throw new Exception("CONTINUITY_BONE_NONFINITE "+id);if(angle>row.maxBoneStep){row.bone=bones[i].name;row.boneFrame=frame;}bone=Mathf.Max(bone,angle);previousRotations[i]=bones[i].localRotation;}
                                if(frame==0){row.firstMorphStep=firstAll;row.firstBoneStep=bone;}
                                row.maxMorphStep=Mathf.Max(row.maxMorphStep,morph);row.maxBoneStep=Mathf.Max(row.maxBoneStep,bone);previousWeights=current;
                            }
                            if(row.firstMorphStep>.12f*60/hz || row.firstBoneStep>6f*60/hz || row.maxMorphStep>.20f*60/hz || row.maxBoneStep>22f*60/hz)
                                throw new Exception("CONTINUITY_SNAP "+id+"/"+label+"/"+hz+" morph="+row.maxMorphStep+" shape="+row.morph+" frame="+row.maxFrame+" first="+row.firstMorphStep+" bone="+row.maxBoneStep+" name="+row.bone+" frame="+row.boneFrame);
                        }
                        Probe(option.id,()=>{if(performance.Replace(option.group,new[]{option.id})!=null)throw new Exception("CONTINUITY_SELECT_FAILED");});
                        Probe(option.id+"/restore",()=>performance.Replace(option.group,Array.Empty<string>()));
                    }
                    // Real skeletal inertia without drift, translation or changing the authored rest pose.
                    avatar.Reset();continuity.Reset();follow.Reset();for(int i=0;i<hz;i++)Tick(dt);
                    var baseline=follow.joints.Select(j=>j.bone.localRotation).ToArray();var positions=follow.joints.Select(j=>j.bone.localPosition).ToArray();
                    var arm=new Case {id=id,option="arm-follow",hz=hz};report.cases.Add(arm);
                    for(int i=0;i<hz;i++){Tick(dt);root.transform.rotation=Quaternion.Euler(0,35*Mathf.Sin(i*dt*6),0);follow.Step(dt);arm.armOffset=Mathf.Max(arm.armOffset,follow.MaximumOffset);}
                    for(int i=0;i<3*hz;i++){Tick(dt);follow.Step(dt);}
                    for(int i=0;i<follow.joints.Length;i++) {
                        arm.armRestError=Mathf.Max(arm.armRestError,CharacterAutonomy.MotionAngle(baseline[i],follow.joints[i].bone.localRotation));
                        if(Vector3.Distance(positions[i],follow.joints[i].bone.localPosition)>.0001f)throw new Exception("ARM_FOLLOW_TRANSLATED_JOINT "+id);
                    }
                    if(arm.armOffset<.1f || arm.armOffset>4.001f || follow.MaximumOffset>.03f)throw new Exception("ARM_FOLLOW_INVALID "+id);
                    // Final animated baseline may move; check restoring is exact against the last raw pose.
                    follow.Restore();for(int i=0;i<follow.joints.Length;i++)if(CharacterAutonomy.MotionAngle(follow.joints[i].raw,follow.joints[i].bone.localRotation)>.001f)throw new Exception("ARM_RESTORE_DRIFT "+id);
                    root.transform.rotation=Quaternion.identity;
                }
                Debug.Log("CONTINUITY_ROLE_PASS "+id);
            }finally {UnityEngine.Object.DestroyImmediate(root);}
        }
        string output=Environment.GetEnvironmentVariable("STARRY_CONTINUITY_REPORT")??Path.Combine(CharacterPackageBuilder.Root,".local/checks/avatar-continuity.json");
        Directory.CreateDirectory(Path.GetDirectoryName(output));File.WriteAllText(output,JsonUtility.ToJson(report,true));
        Debug.Log("AVATAR_CONTINUITY_PASS roles="+CharacterPackageBuilder.Roster.characters.Length+" cases="+report.cases.Count);
    }
}
