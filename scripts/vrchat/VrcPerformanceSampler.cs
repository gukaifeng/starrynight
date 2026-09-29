using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

// Trusted, offline sampling of author-owned AnimationClips on their original Avatar.
// No source controllers, MonoBehaviours, SDK components or events are executed.
public static class VrcPerformanceSampler
{
    [Serializable] public class Report { public int schemaVersion=1; public string role; public Rest[] rest; public Motion[] motions; public MorphMotion[] morphMotions; }
    [Serializable] public class MorphMotion { public string path; public MorphTrack[] tracks; }
    [Serializable] public class MorphTrack { public string renderer,shape; public float[] times,values; }
    [Serializable] public class Rest { public string path; public Vector3 position; public Quaternion rotation,worldRotation,parentWorldRotation; }
    [Serializable] public class Motion { public string path,name; public float duration; public bool humanoid,loop; public Track[] tracks; public float maxAngle,maxDistance; }
    [Serializable] public class Track { public string path; public float[] times; public Quaternion[] rotations; public Vector3[] positions; }
    static string PathOf(Transform t, Transform root) => AnimationUtility.CalculateTransformPath(t,root);
    public static void Export()
    {
        var config=JsonUtility.FromJson<VrcSourceInspector.Specs>(File.ReadAllText("InspectionConfig.json"));
        Directory.CreateDirectory("Inspection/Performances");
        foreach(var spec in config.specs)
        {
            var asset=AssetDatabase.LoadAssetAtPath<GameObject>(spec.fbx);
            var source=UnityEngine.Object.Instantiate(asset); source.transform.SetPositionAndRotation(Vector3.zero,Quaternion.identity);
            var animator=source.GetComponent<Animator>();
            if(!animator || !animator.avatar || !animator.avatar.isHuman) throw new Exception("VRC_PERFORMANCE_AVATAR_INVALID "+spec.role);
            animator.runtimeAnimatorController=null; animator.applyRootMotion=true; animator.enabled=true;
            var transforms=source.GetComponentsInChildren<Transform>(true);
            var rest=transforms.Select(t=>new Rest { path=PathOf(t,source.transform),position=t.localPosition,rotation=t.localRotation,worldRotation=t.rotation,parentWorldRotation=t.parent?t.parent.rotation:Quaternion.identity }).ToArray();
            var human=new HashSet<string>();
            foreach(HumanBodyBones bone in Enum.GetValues(typeof(HumanBodyBones)))
                if(bone!=HumanBodyBones.LastBone && bone!=HumanBodyBones.LeftEye && bone!=HumanBodyBones.RightEye && bone!=HumanBodyBones.Jaw)
                { var t=animator.GetBoneTransform(bone); if(t) human.Add(PathOf(t,source.transform)); }
            var motions=new List<Motion>(); var morphMotions=new List<MorphMotion>();
            string directory=Path.GetDirectoryName(Path.GetDirectoryName(spec.fbx)).Replace('\\','/');
            foreach(string file in Directory.GetFiles(directory,"*.anim",SearchOption.AllDirectories).OrderBy(x=>x,StringComparer.Ordinal))
            {
                string path=file.Replace('\\','/'); var clip=AssetDatabase.LoadAssetAtPath<AnimationClip>(path);
                var bindings=AnimationUtility.GetCurveBindings(clip);
                var shapeBindings=bindings.Where(b=>b.type==typeof(SkinnedMeshRenderer) && b.propertyName.StartsWith("blendShape.",StringComparison.Ordinal)).ToArray();
                if(shapeBindings.Length>0)
                {
                    float len=Mathf.Max(clip.length,1f/60); int size=Mathf.Max(2,Mathf.CeilToInt(len*60)+1);
                    var sampledTimes=Enumerable.Range(0,size).Select(i=>len*i/(size-1)).ToArray();
                    morphMotions.Add(new MorphMotion {path=path,tracks=shapeBindings.Select(b=>{
                        var curve=AnimationUtility.GetEditorCurve(clip,b);
                        return new MorphTrack {renderer=b.path,shape=b.propertyName.Substring(11),times=sampledTimes,values=sampledTimes.Select(t=>curve.Evaluate(Mathf.Min(t,clip.length))/100f).ToArray()};
                    }).ToArray()});
                }
                var transformPaths=new HashSet<string>(bindings.Where(b=>b.type==typeof(Transform)).Select(b=>b.path));
                bool humanoid=bindings.Any(b=>b.type==typeof(Animator));
                if(!humanoid && transformPaths.Count==0) continue;
                bool hand=path.Contains("HandGesture/") || (spec.role=="mamehinata" && new[]{"_gun","_rock","_thumbs_up","_open","_hands_idle","_peace","_point","_fist"}.Any(s=>clip.name.EndsWith(s,StringComparison.Ordinal)));
                var paths=new HashSet<string>(transformPaths);
                if(humanoid) foreach(var bone in human) if(!hand || bone.Contains("/Hand.")) paths.Add(bone);
                paths.Remove("");
                var selected=Enumerable.Range(0,transforms.Length).Where(i=>paths.Contains(rest[i].path)).ToArray();
                if(selected.Length==0) continue;
                float length=Mathf.Max(clip.length,1f/60); int count=Mathf.Max(2,Mathf.CeilToInt(length*60)+1);
                var times=Enumerable.Range(0,count).Select(i=>length*i/(count-1)).ToArray();
                var tracks=selected.Select(i=>new Track { path=rest[i].path,times=times,rotations=new Quaternion[count],positions=new Vector3[count] }).ToArray();
                float angle=0,distance=0;
                for(int frame=0;frame<count;frame++)
                {
                    for(int i=0;i<transforms.Length;i++) { transforms[i].localPosition=rest[i].position; transforms[i].localRotation=rest[i].rotation; }
                    clip.SampleAnimation(source,Mathf.Min(times[frame],clip.length));
                    for(int k=0;k<selected.Length;k++)
                    {
                        int i=selected[k]; var t=transforms[i];
                        tracks[k].rotations[frame]=t.localRotation; tracks[k].positions[frame]=t.localPosition;
                        angle=Mathf.Max(angle,Quaternion.Angle(rest[i].rotation,t.localRotation));
                        distance=Mathf.Max(distance,Vector3.Distance(rest[i].position,t.localPosition));
                    }
                }
                motions.Add(new Motion { path=path,name=clip.name,duration=clip.length,humanoid=humanoid,loop=AnimationUtility.GetAnimationClipSettings(clip).loopTime,tracks=tracks,maxAngle=angle,maxDistance=distance });
                Debug.Log("VRC_PERFORMANCE_SAMPLED "+spec.role+" "+clip.name+" tracks="+tracks.Length+" angle="+angle+" distance="+distance);
            }
            File.WriteAllText("Inspection/Performances/"+spec.role+".json",JsonUtility.ToJson(new Report {role=spec.role,rest=rest,motions=motions.ToArray(),morphMotions=morphMotions.ToArray()})+"\n");
            UnityEngine.Object.DestroyImmediate(source);
        }
    }
}
