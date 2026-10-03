using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using ModelSpace;

// Measure the saved production prefabs against their actual Idle baseline.
// A humanoid hand gesture must not replace the standing upper-arm pose.
public static class AvatarIdleArmReview
{
    [Serializable] class Human {public string human,path;}
    [Serializable] class Geometry {public Human[] human;}
    [Serializable] class Arm {public string side;public float baselineDown,finalDown,upperDelta,lowerDelta;public List<string> overridingLayers=new List<string>();}
    [Serializable] class Role {public string id;public List<Arm> arms=new List<Arm>();public int physicalSegments,physicalArmSegments;}
    [Serializable] class Report {public string scope="Saved prefab / Editor bone evaluation, not real-time device performance";public List<Role> roles=new List<Role>();}
    public static void Run()
    {
        EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);
        var report=new Report();
        foreach(string id in CharacterPackageBuilder.Roster.characters)
        {
            string folder="Assets/CharacterPackages/Imported/"+id;
            var geometry=JsonUtility.FromJson<Geometry>(File.ReadAllText(folder+"/avatar-geometry.json"));
            var prefab=AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Prefabs/Package_"+id+".prefab");
            if(!prefab)throw new Exception("ARM_PREFAB_MISSING "+id);
            var root=UnityEngine.Object.Instantiate(prefab);root.SetActive(true);
            try {
                foreach(var b in root.GetComponentsInChildren<MonoBehaviour>(true))b.enabled=false;
                var player=root.GetComponentInChildren<Animation>(true);player.enabled=false;
                player.GetClip("Idle").SampleAnimation(root,0);
                var avatar=root.GetComponent<AvatarControlDriver>();
                var row=new Role {id=id};report.roles.Add(row);
                var physics=root.GetComponent<AvatarSecondaryMotion>();row.physicalSegments=physics?physics.strands.Length:0;
                foreach(string side in new[]{"Left","Right"}) {
                    Transform Bone(string name) {var path=geometry.human.FirstOrDefault(h=>h.human==side+name)?.path;return path==null?null:root.transform.Find("Avatar/"+path);}
                    var upper=Bone("UpperArm");var lower=Bone("LowerArm");var hand=Bone("Hand");if(!upper || !lower || !hand)throw new Exception("ARM_MAPPING_MISSING "+id+"/"+side);
                    if(physics)row.physicalArmSegments+=physics.strands.Count(s=>s.bone==upper || s.bone==lower || s.bone==hand);
                    var qUpper=upper.localRotation;var qLower=lower.localRotation;
                    var arm=new Arm {side=side,baselineDown=Vector3.Dot((hand.position-upper.position).normalized,-root.transform.up)};row.arms.Add(arm);
                    if(avatar) {
                        avatar.animator.enabled=true;avatar.Reset();if(avatar.animator.layerCount<1)throw new Exception("ARM_CONTROLLER_UNBOUND "+id);
                        for(int i=0;i<120;i++){avatar.AdvanceWeights(1f/60);avatar.animator.Update(1f/60);}
                        arm.finalDown=Vector3.Dot((hand.position-upper.position).normalized,-root.transform.up);
                        arm.upperDelta=Quaternion.Angle(qUpper,upper.localRotation);arm.lowerDelta=Quaternion.Angle(qLower,lower.localRotation);
                        if(arm.upperDelta>5 || arm.lowerDelta>5)for(int layer=1;layer<avatar.animator.layerCount;layer++) {
                            avatar.Reset();avatar.animator.SetLayerWeight(layer,0);
                            for(int i=0;i<120;i++)avatar.animator.Update(1f/60);
                            if(Quaternion.Angle(qUpper,upper.localRotation)<arm.upperDelta-3 || Quaternion.Angle(qLower,lower.localRotation)<arm.lowerDelta-3)
                                arm.overridingLayers.Add(avatar.animator.GetLayerName(layer));
                        }
                    }else {arm.finalDown=arm.baselineDown;}
                    player.GetClip("Idle").SampleAnimation(root,0);
                }
                Debug.Log("IDLE_ARM_REVIEW "+id+" "+string.Join(" / ",row.arms.Select(a=>a.side+" down="+a.finalDown.ToString("F3")+" delta="+a.upperDelta.ToString("F2")+" layers="+string.Join(",",a.overridingLayers))));
            }finally{UnityEngine.Object.DestroyImmediate(root);}
        }
        string output=Environment.GetEnvironmentVariable("STARRY_ARM_REPORT")??Path.Combine(CharacterPackageBuilder.Root,".local/checks/idle-arms.json");
        Directory.CreateDirectory(Path.GetDirectoryName(output));File.WriteAllText(output,JsonUtility.ToJson(report,true));
        Debug.Log("IDLE_ARM_REVIEW_DONE roles="+report.roles.Count);
    }
}
