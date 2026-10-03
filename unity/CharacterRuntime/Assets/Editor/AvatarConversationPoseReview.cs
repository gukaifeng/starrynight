using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using ModelSpace;

// Exercise the actual exported controller. Original poses remain available for
// manual preview; normal idle/AI gesture controls must keep the torso upright.
public static class AvatarConversationPoseReview
{
    public static void RebuildAndRun(){BuildIos.Setup();AssetDatabase.SaveAssets();Run();}
    public static void RebuildControllersAndRun() {
        foreach(string id in CharacterPackageBuilder.Roster.characters) {
            string path="Assets/Prefabs/Package_"+id+".prefab";
            var root=PrefabUtility.LoadPrefabContents(path);
            try {
                var control=root.GetComponent<AvatarControlDriver>();if(!control)continue;
                var player=root.GetComponentInChildren<Animation>(true);var idle=player.GetClip("Idle");
                var behaviors=root.GetComponentsInChildren<MonoBehaviour>(true).Select(b=>(behavior:b,wasEnabled:b.enabled)).ToArray();
                foreach(var entry in behaviors)entry.behavior.enabled=false;
                UnityEngine.Object.DestroyImmediate(control.animator);UnityEngine.Object.DestroyImmediate(control);
                root.SetActive(true);idle.SampleAnimation(root,0);
                PortableAvatarControllerBuilder.Prepare(root,"Assets/CharacterPackages/Imported/"+id,idle);
                foreach(var entry in behaviors)if(entry.behavior)entry.behavior.enabled=entry.wasEnabled;
                root.SetActive(false);
                foreach(string target in new[]{path,"Assets/Resources/Characters/"+id+".prefab",CharacterBundleBuilder.Prefab(id)})
                    if(File.Exists(target))PrefabUtility.SaveAsPrefabAsset(root,target);
            } finally {PrefabUtility.UnloadPrefabContents(root);}
        }
        AssetDatabase.SaveAssets();AssetDatabase.Refresh();Run();
    }
    [Serializable] public class Case {public string id,option;public float maxHipDegrees,maxHeadDisplacement,minUpright=1,maxFrameDegrees;public bool finite=true;}
    [Serializable] public class Report {public string scope="Editor Animator / CPU bone evaluation, not device FPS";public List<Case> cases=new List<Case>();}
    public static void Run()
    {
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);
        var report=new Report();
        foreach(string id in CharacterPackageBuilder.Roster.characters)
        {
            if(Environment.GetEnvironmentVariable("STARRY_POSE_ONLY") is string only && only!=id)continue;
            var prefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Resources/Characters/"+id+".prefab");
            if(!prefab)prefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Prefabs/Package_"+id+".prefab");
            if(!prefab)throw new Exception("POSE_PREFAB_MISSING "+id);
            var root=UnityEngine.Object.Instantiate(prefab);root.SetActive(true);
            try {
                foreach(var behavior in root.GetComponentsInChildren<MonoBehaviour>(true))behavior.enabled=false;
                var character=root.GetComponent<ViewerCharacter>();var avatar=root.GetComponent<AvatarControlDriver>();
                var player=root.GetComponentInChildren<Animation>(true);player.enabled=false;
                var idle=player.GetClip("Idle");idle.SampleAnimation(root,0);
                if(avatar && Environment.GetEnvironmentVariable("STARRY_POSE_REBUILD")=="1") {
                    UnityEngine.Object.DestroyImmediate(avatar.animator);UnityEngine.Object.DestroyImmediate(avatar);
                    PortableAvatarControllerBuilder.Prepare(root,"Assets/CharacterPackages/Imported/"+id,idle);avatar=root.GetComponent<AvatarControlDriver>();
                }
                var head=CharacterContract.Resolve(root.transform,character.Manifest.rig.head);
                var hips=root.GetComponentsInChildren<Transform>(true).FirstOrDefault(t=>t.name.Equals("Hips",StringComparison.OrdinalIgnoreCase));
                if(!hips)hips=head.parent;
                Vector3 h0=head.position,p0=hips.position;Quaternion q0=hips.localRotation;
                Vector3 axis0=(head.position-hips.position).normalized;float height=Mathf.Max(.01f,character.RestBounds().size.y);
                if(avatar){avatar.animator.enabled=true;avatar.animator.Rebind();avatar.animator.Update(0);if(avatar.animator.layerCount<1)throw new Exception("POSE_CONTROLLER_UNBOUND "+id);}else {player.enabled=true;player.Play("Idle");}
                var performance=root.AddComponent<CharacterPerformanceDriver>();performance.Bind(character);
                void Probe(string option,int frames) {
                    if(avatar)avatar.Reset();else {player.Stop();player.Play("Idle");}
                    if(avatar && Environment.GetEnvironmentVariable("STARRY_POSE_DISABLE_ADDITIVE")=="1")avatar.Weight(2,-1,0,0);
                    var row=new Case{id=id,option=option};report.cases.Add(row);
                    if(option!="idle" && performance.Replace(character.Manifest.performance.options.First(o=>o.id==option).group,new[]{option})!=null)throw new Exception("POSE_SELECT_FAILED "+id+"/"+option);
                    var previous=hips.localRotation;
                    for(int f=0;f<frames;f++) {
                        if(avatar){avatar.AdvanceWeights(1f/60);avatar.animator.Update(1f/60);}else {performance.RestoreMorphs();performance.Step(1f/60);foreach(AnimationState state in player)if(state.enabled)state.time+=1f/60;player.Sample();performance.ApplyFrame();}
                        row.maxHipDegrees=Mathf.Max(row.maxHipDegrees,Quaternion.Angle(q0,hips.localRotation));
                        row.maxFrameDegrees=Mathf.Max(row.maxFrameDegrees,Quaternion.Angle(previous,hips.localRotation));previous=hips.localRotation;
                        row.maxHeadDisplacement=Mathf.Max(row.maxHeadDisplacement,Vector3.Distance(head.position,h0)/height);
                        row.minUpright=Mathf.Min(row.minUpright,Vector3.Dot(axis0,(head.position-hips.position).normalized));
                        row.finite &= float.IsFinite(head.position.x+head.position.y+head.position.z+hips.localRotation.x+hips.localRotation.y+hips.localRotation.z+hips.localRotation.w);
                    }
                }
                Probe("idle",id=="anime-hikarun"?1800:600);
                foreach(var option in (character.Manifest.performance?.options??Array.Empty<CharacterPerformanceOption>()).Where(o=>o.ai?.automatic==true))Probe(option.id,120);
                Debug.Log("CONVERSATION_POSE_ROLE_DONE "+id);
            } finally {UnityEngine.Object.DestroyImmediate(root);}
        }
        string path=Environment.GetEnvironmentVariable("STARRY_POSE_REPORT")??Path.Combine(CharacterPackageBuilder.Root,".local/checks/conversation-pose.json");Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,JsonUtility.ToJson(report,true));
        var failures=report.cases.Where(r=>!r.finite || r.maxHipDegrees>35 || r.minUpright<.85f || r.maxHeadDisplacement>.25f).ToArray();
        Debug.Log("CONVERSATION_POSE_REVIEW cases="+report.cases.Count+" unsafe="+failures.Length+" path="+path);
        if(Environment.GetEnvironmentVariable("STARRY_POSE_ASSERT")=="1" && failures.Length>0)throw new Exception("CONVERSATION_POSE_UNSAFE "+string.Join(",",failures.Select(r=>r.id+"/"+r.option)));
    }
}
