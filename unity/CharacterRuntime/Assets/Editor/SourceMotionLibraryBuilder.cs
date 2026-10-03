using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using ModelSpace;

public static class SourceMotionLibraryBuilder
{
    [Serializable] public sealed class Library {public int schemaVersion;public string parameter;public Motion[] motions;}
    [Serializable] public sealed class Motion {public string guid,name,category,intent;public float duration;public bool loop;public float[] times;public Track[] tracks;public Curve[] curves;}
    [Serializable] public sealed class Track {public string path;public float[] times;public Vector3[] positions,scales;public Quaternion[] rotations;}
    [Serializable] public sealed class Curve {public string path,component,property;public Key[] keys;}
    [Serializable] public sealed class Key {public float time,value,inTangent,outTangent,inWeight,outWeight;public int weightedMode;public bool steppedIn,steppedOut;}
    public static void Prepare(GameObject actor,string folder)
    {
        string path=folder+"/source-motions.json";if(!File.Exists(path+".gz"))return;
        var data=JsonUtility.FromJson<Library>(CharacterMotionData.Read(path));
        if(data.schemaVersion!=1 || data.parameter!=SourceMotionPreview.Parameter || data.motions.Length>2048)throw new Exception("SOURCE_LIBRARY_INVALID");
        var root=actor.transform.Find("Avatar");if(!root)throw new Exception("SOURCE_LIBRARY_ROOT_MISSING");
        string asset=folder+"/BakedControllers/SourceMotions.asset";
        if(File.Exists(asset))AssetDatabase.DeleteAsset(asset);
        var holder=ScriptableObject.CreateInstance<SourceMotionLibraryAsset>();AssetDatabase.CreateAsset(holder,asset);
        var driver=actor.AddComponent<SourceMotionPreview>();driver.avatar=root.gameObject;
        var entries=new List<SourceMotionPreview.Entry>();
        foreach(var source in data.motions){
            var clip=new AnimationClip {name=source.name,legacy=false,frameRate=60};AssetDatabase.AddObjectToAsset(clip,holder);
            var nodes=new Dictionary<string,SourceMotionPreview.Node>();var morphs=new Dictionary<string,SourceMotionPreview.Morph>();var visible=new Dictionary<string,SourceMotionPreview.Visible>();
            Transform Resolve(string p){var t=root.Find(p);if(!t)throw new Exception("SOURCE_MOTION_BINDING_MISSING: "+source.name+"/"+p);return t;}
            SourceMotionPreview.Node Node(string p){if(!nodes.TryGetValue(p,out var n)){n=new SourceMotionPreview.Node {target=Resolve(p)};nodes[p]=n;}return n;}
            foreach(var t in source.tracks){
                Node(t.path).transform=true;
                var times=t.times?.Length>0?t.times:source.times;
                void Axis(string prop,int axis){
                    var keys=times.Select((time,i)=>new Keyframe(time,prop=="m_LocalPosition"?t.positions[i][axis]:prop=="m_LocalScale"?t.scales[i][axis]:t.rotations[i][axis])).ToArray();
                    var curve=new AnimationCurve(keys);
                    for(int i=0;i<keys.Length;i++){AnimationUtility.SetKeyLeftTangentMode(curve,i,AnimationUtility.TangentMode.Linear);AnimationUtility.SetKeyRightTangentMode(curve,i,AnimationUtility.TangentMode.Linear);}
                    AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(t.path,typeof(Transform),prop+"."+"xyzw"[axis]),curve);
                }
                for(int axis=0;axis<3;axis++){Axis("m_LocalPosition",axis);Axis("m_LocalScale",axis);}for(int axis=0;axis<4;axis++)Axis("m_LocalRotation",axis);
            }
            foreach(var c in source.curves){
                Type type=c.component=="UnityEngine.GameObject"?typeof(GameObject):c.component=="UnityEngine.SkinnedMeshRenderer"?typeof(SkinnedMeshRenderer):typeof(MeshRenderer);
                float scale=1;var target=Resolve(c.path);
                if(c.property.StartsWith("blendShape.",StringComparison.Ordinal)){
                    var skin=target.GetComponent<SkinnedMeshRenderer>();int index=skin?skin.sharedMesh.GetBlendShapeIndex(c.property.Substring(11)):-1;
                    if(index<0)throw new Exception("SOURCE_MORPH_MISSING: "+source.name+"/"+c.property);
                    scale=CharacterContract.MorphScale(skin,index)/100;
                    morphs[c.path+"/"+index]=new SourceMotionPreview.Morph {skin=skin,index=index};
                }else if(c.property=="m_IsActive")Node(c.path).active=true;
                else if(c.property=="m_Enabled"){var renderer=target.GetComponent<Renderer>();if(!renderer)throw new Exception("SOURCE_RENDERER_MISSING");visible[c.path]=new SourceMotionPreview.Visible {target=renderer};}
                else throw new Exception("SOURCE_CURVE_NOT_ALLOWLISTED: "+c.property);
                var values=c.keys.Select(k=>new Keyframe(k.time,k.value*scale,k.steppedIn?float.PositiveInfinity:k.inTangent*scale,k.steppedOut?float.PositiveInfinity:k.outTangent*scale,k.inWeight,k.outWeight){weightedMode=(WeightedMode)k.weightedMode}).ToArray();
                AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(c.path,type,c.property),new AnimationCurve(values));
            }
            clip.EnsureQuaternionContinuity();
            entries.Add(new SourceMotionPreview.Entry {id="source-motion-"+source.guid,label=source.name,category=source.category,intent=source.intent,
                clip=clip,duration=source.duration,loop=source.loop,nodes=nodes.Values.ToArray(),morphs=morphs.Values.ToArray(),visible=visible.Values.ToArray()});
        }
        driver.entries=entries.ToArray();actor.AddComponent<SourceMotionPreviewRestore>().driver=driver;
        EditorUtility.SetDirty(holder);
    }
}
