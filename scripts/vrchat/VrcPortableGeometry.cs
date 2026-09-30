using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

// Trusted build-time reader. Never executes the supplied Animator controllers,
// AnimationEvents, scripts or SDK. Exports the instantiated author prefab, not a
// guessed FBX bind pose; all node paths stay stable through portable conversion.
public static class VrcPortableGeometry
{
    [Serializable] public class Slice { public long offset; public int count,width; public string type; }
    [Serializable] public class Node { public string path,name; public int parent; public bool active; public Vector3 position,scale; public Quaternion rotation; }
    [Serializable] public class Shape { public string name; public float weight; public Frame[] frames; }
    [Serializable] public class Frame { public float weight; public Slice position,normal; }
    [Serializable] public class Primitive { public Slice indices; public string material,guid; public int sourceSubmesh; }
    [Serializable] public class Skin { public string path; public bool active,enabled; public int vertices; public Slice position,normal,uv,joints,weights,bindposes; public string[] bones; public Primitive[] primitives; public Shape[] shapes; }
    [Serializable] public class Report { public int schemaVersion=1; public string role,prefab; public Node[] nodes; public Skin[] skins; public VrcSourceInspector.Bone[] human; public string[] limitations; }
    [Serializable] public class Key { public float time,value,inTangent,outTangent,inWeight,outWeight; public int weightedMode; }
    [Serializable] public class Curve { public string path,component,property; public Key[] keys; }
    [Serializable] public class ObjectKey { public float time; public string guid,path; public long fileID; }
    [Serializable] public class ObjectCurve { public string path,component,property; public ObjectKey[] keys; }
    [Serializable] public class TransformTrack { public string path; public Vector3[] positions,scales; public Quaternion[] rotations; }
    [Serializable] public class Motion { public string path,name,guid; public bool humanoid,loop; public string[] humanoidProperties;public float duration; public float[] times; public TransformTrack[] tracks; public Curve[] curves; public ObjectCurve[] objects; public int omittedEventCount; }
    [Serializable] public class Motions { public int schemaVersion=1; public string role; public Motion[] motions; }
    static string PathOf(Transform t,Transform root) => t==root?"":AnimationUtility.CalculateTransformPath(t,root);
    sealed class Buffer : IDisposable
    {
        readonly BinaryWriter writer;
        public Buffer(string path) { writer=new BinaryWriter(File.Create(path)); }
        public Slice Floats(float[] values,int width)
        {
            var slice=new Slice { offset=writer.BaseStream.Position,count=values.Length/width,width=width,type="f32" };
            foreach(float value in values) { if(!float.IsFinite(value))throw new Exception("NONFINITE_GEOMETRY");writer.Write(value); }
            return slice;
        }
        public Slice Vectors(Vector3[] values) => Floats(values.SelectMany(v=>new[]{v.x,v.y,v.z}).ToArray(),3);
        public Slice Ints(int[] values,int width=1)
        {
            var slice=new Slice { offset=writer.BaseStream.Position,count=values.Length/width,width=width,type="i32" };
            foreach(int value in values)writer.Write(value);return slice;
        }
        public void Dispose()=>writer.Dispose();
    }
    public static void Export()
    {
        VrcSourceInspector.Export();
        var config=JsonUtility.FromJson<VrcSourceInspector.Specs>(File.ReadAllText("InspectionConfig.json"));
        foreach(var spec in config.specs)Export(spec);
    }
    static void Export(VrcSourceInspector.Spec spec)
    {
        string output="Inspection/Portable/"+spec.role;Directory.CreateDirectory(output);
        // Force source meshes readable in this isolated project only.
        foreach(string guid in AssetDatabase.FindAssets("t:Model"))
        {
            var importer=AssetImporter.GetAtPath(AssetDatabase.GUIDToAssetPath(guid)) as ModelImporter;
            if(importer && !importer.isReadable) { importer.isReadable=true;importer.SaveAndReimport(); }
        }
        var asset=AssetDatabase.LoadAssetAtPath<GameObject>(spec.prefab);
        var go=UnityEngine.Object.Instantiate(asset);go.name=asset.name;
        var root=go.transform;
        foreach(var component in go.GetComponentsInChildren<Animator>(true)) {component.runtimeAnimatorController=null;component.enabled=false;}
        var transforms=root.GetComponentsInChildren<Transform>(true);
        var byTransform=transforms.Select((t,i)=>(t,i)).ToDictionary(x=>x.t,x=>x.i);
        var nodes=transforms.Select(t=>new Node {path=PathOf(t,root),name=t.name,parent=t==root?-1:byTransform[t.parent],active=t.gameObject.activeSelf,position=t.localPosition,rotation=t.localRotation,scale=t.localScale}).ToArray();
        var limitations=new List<string>();var skins=new List<Skin>();
        using(var buffer=new Buffer(output+"/geometry.bin"))
        foreach(var renderer in root.GetComponentsInChildren<Renderer>(true))
        {
            Mesh mesh=null;var skin=renderer as SkinnedMeshRenderer;
            if(skin)mesh=skin.sharedMesh;
            else if(renderer is MeshRenderer)mesh=renderer.GetComponent<MeshFilter>()?.sharedMesh;
            else {limitations.Add("Renderer component requires separate adapter: "+renderer.GetType().Name+" "+PathOf(renderer.transform,root));continue;}
            if(!mesh) { limitations.Add("Renderer has no source mesh: "+PathOf(renderer.transform,root));continue; }
            var primitives=new List<Primitive>();var materials=renderer.sharedMaterials;
            for(int slot=0;slot<Math.Max(mesh.subMeshCount,materials.Length);slot++)
            {
                int submesh=Math.Min(slot,mesh.subMeshCount-1);
                if(mesh.GetTopology(submesh)!=MeshTopology.Triangles)throw new Exception("NON_TRIANGULAR_SOURCE_MESH");
                var material=slot<materials.Length?materials[slot]:null;
                primitives.Add(new Primitive {indices=buffer.Ints(mesh.GetIndices(submesh)),material=material?material.name:"missing",guid=material?AssetDatabase.AssetPathToGUID(AssetDatabase.GetAssetPath(material)):"",sourceSubmesh=submesh});
            }
            var shapes=new List<Shape>();
            for(int i=0;i<mesh.blendShapeCount;i++)
            {
                var frames=new List<Frame>();
                for(int j=0;j<mesh.GetBlendShapeFrameCount(i);j++)
                {
                    var positions=new Vector3[mesh.vertexCount];var normals=new Vector3[mesh.vertexCount];
                    mesh.GetBlendShapeFrameVertices(i,j,positions,normals,null);
                    frames.Add(new Frame {weight=mesh.GetBlendShapeFrameWeight(i,j),position=buffer.Vectors(positions),normal=buffer.Vectors(normals)});
                }
                shapes.Add(new Shape {name=mesh.GetBlendShapeName(i),weight=skin?skin.GetBlendShapeWeight(i):0,frames=frames.ToArray()});
            }
            Slice joints=null,weights=null,bindposes=null;string[] bones=Array.Empty<string>();
            if(skin && skin.bones.Length>0)
            {
                var perVertex=mesh.GetBonesPerVertex();var all=mesh.GetAllBoneWeights();
                int width=perVertex.Max(x=>(int)x);width=Math.Max(4,((width+3)/4)*4);
                var indices=new int[mesh.vertexCount*width];var values=new float[mesh.vertexCount*width];int cursor=0;
                for(int v=0;v<perVertex.Length;v++)for(int w=0;w<perVertex[v];w++)
                {indices[v*width+w]=all[cursor].boneIndex;values[v*width+w]=all[cursor].weight;cursor++;}
                joints=buffer.Ints(indices,width);weights=buffer.Floats(values,width);
                bones=skin.bones.Select(t=>t?PathOf(t,root):throw new Exception("MISSING_SKIN_BONE")).ToArray();
                bindposes=buffer.Floats(mesh.bindposes.SelectMany(m=>Enumerable.Range(0,16).Select(i=>m[i])).ToArray(),16);
                perVertex.Dispose();all.Dispose();
            }
            skins.Add(new Skin {path=PathOf(renderer.transform,root),active=renderer.gameObject.activeInHierarchy,enabled=renderer.enabled,vertices=mesh.vertexCount,
                position=buffer.Vectors(mesh.vertices),normal=buffer.Vectors(mesh.normals),uv=buffer.Floats(mesh.uv.SelectMany(v=>new[]{v.x,v.y}).ToArray(),2),
                joints=joints,weights=weights,bindposes=bindposes,bones=bones,primitives=primitives.ToArray(),shapes=shapes.ToArray()});
        }
        var inspection=JsonUtility.FromJson<VrcSourceInspector.Report>(File.ReadAllText("Inspection/"+spec.role+"-prefab.json"));
        var report=new Report {role=spec.role,prefab=spec.prefab,nodes=nodes,skins=skins.ToArray(),human=inspection.human,limitations=limitations.ToArray()};
        File.WriteAllText(output+"/geometry.json",JsonUtility.ToJson(report,true)+"\n");
        Sample(spec,go,nodes,output);
        UnityEngine.Object.DestroyImmediate(go);
        Debug.Log("VRC_PORTABLE_EXPORTED "+spec.role+" skins="+skins.Count+" nodes="+nodes.Length);
    }
    static void Sample(VrcSourceInspector.Spec spec,GameObject go,Node[] rest,string output)
    {
        var root=go.transform;var animator=go.GetComponent<Animator>();
        if(animator) {animator.runtimeAnimatorController=null;animator.enabled=true;animator.applyRootMotion=true;}
        var transforms=root.GetComponentsInChildren<Transform>(true);var reports=new List<Motion>();
        var humanPaths=new HashSet<string>();
        if(animator && animator.avatar && animator.avatar.isHuman)
            foreach(HumanBodyBones bone in Enum.GetValues(typeof(HumanBodyBones)))
                if(bone!=HumanBodyBones.LastBone) {var t=animator.GetBoneTransform(bone);if(t)humanPaths.Add(PathOf(t,root));}
        foreach(string file in Directory.GetFiles("Assets","*.anim",SearchOption.AllDirectories).OrderBy(x=>x,StringComparer.Ordinal))
        {
            string path=file.Replace('\\','/');var clip=AssetDatabase.LoadAssetAtPath<AnimationClip>(path);
            if(!clip)throw new Exception("SOURCE_CLIP_MISSING: "+path);
            var bindings=AnimationUtility.GetCurveBindings(clip);
            var muscles=new System.Collections.Generic.HashSet<string>(HumanTrait.MuscleName);
            var humanoidProperties=bindings.Where(b=>b.type==typeof(Animator) &&
                (muscles.Contains(b.propertyName) || b.propertyName.StartsWith("RootT.",StringComparison.Ordinal) || b.propertyName.StartsWith("RootQ.",StringComparison.Ordinal) ||
                 b.propertyName.StartsWith("LeftHand.",StringComparison.Ordinal) || b.propertyName.StartsWith("RightHand.",StringComparison.Ordinal)))
                .Select(b=>b.propertyName).ToArray();
            bool humanoid=humanoidProperties.Length>0;
            bool fingersOnly=humanoid && humanoidProperties.All(p=>p.StartsWith("LeftHand.",StringComparison.Ordinal) || p.StartsWith("RightHand.",StringComparison.Ordinal));
            var affected=new HashSet<string>(bindings.Where(b=>b.type==typeof(Transform)).Select(b=>b.path));
            if(humanoid)foreach(HumanBodyBones bone in Enum.GetValues(typeof(HumanBodyBones)))
                if(bone!=HumanBodyBones.LastBone && (!fingersOnly || (bone>=HumanBodyBones.LeftThumbProximal && bone<=HumanBodyBones.RightLittleDistal)))
                {var t=animator.GetBoneTransform(bone);if(t)affected.Add(PathOf(t,root));}
            var indices=Enumerable.Range(0,transforms.Length).Where(i=>affected.Contains(rest[i].path)).ToArray();
            if(clip.length>600)throw new Exception("SOURCE_CLIP_TOO_LONG_FOR_PORTABLE_PROFILE: "+path);
            int count=clip.length>0?Math.Max(2,Mathf.CeilToInt(clip.length*60)+1):2;
            float duration=clip.length>0?clip.length:1;
            var times=Enumerable.Range(0,count).Select(i=>duration*i/(count-1)).ToArray();
            var tracks=indices.Select(i=>new TransformTrack {path=rest[i].path,positions=new Vector3[count],rotations=new Quaternion[count],scales=new Vector3[count]}).ToArray();
            if(indices.Length>0)for(int frame=0;frame<count;frame++)
            {
                for(int i=0;i<rest.Length;i++) {transforms[i].localPosition=rest[i].position;transforms[i].localRotation=rest[i].rotation;transforms[i].localScale=rest[i].scale;}
                clip.SampleAnimation(go,Math.Min(times[frame],clip.length));
                for(int j=0;j<indices.Length;j++) {var t=transforms[indices[j]];tracks[j].positions[frame]=t.localPosition;tracks[j].rotations[frame]=t.localRotation;tracks[j].scales[frame]=t.localScale;}
            }
            var curves=bindings.Where(b=>b.type!=typeof(Transform)).Select(b=>new Curve {
                path=b.path,component=b.type.FullName,property=b.propertyName,
                keys=AnimationUtility.GetEditorCurve(clip,b).keys.Select(k=>new Key {time=k.time,value=k.value,inTangent=k.inTangent,outTangent=k.outTangent,inWeight=k.inWeight,outWeight=k.outWeight,weightedMode=(int)k.weightedMode}).ToArray()}).ToArray();
            var objects=AnimationUtility.GetObjectReferenceCurveBindings(clip).Select(b=>new ObjectCurve {path=b.path,component=b.type.FullName,property=b.propertyName,
                keys=AnimationUtility.GetObjectReferenceCurve(clip,b).Select(k=>{string guid="";long id=0;if(k.value)AssetDatabase.TryGetGUIDAndLocalFileIdentifier(k.value,out guid,out id);return new ObjectKey {time=k.time,guid=guid,fileID=id,path=k.value?AssetDatabase.GetAssetPath(k.value):""};}).ToArray()}).ToArray();
            reports.Add(new Motion {path=path,name=clip.name,guid=AssetDatabase.AssetPathToGUID(path),humanoid=humanoid,humanoidProperties=humanoidProperties,loop=AnimationUtility.GetAnimationClipSettings(clip).loopTime,duration=clip.length,times=times,tracks=tracks,curves=curves,objects=objects,omittedEventCount=AnimationUtility.GetAnimationEvents(clip).Length});
        }
        File.WriteAllText(output+"/motions.json",JsonUtility.ToJson(new Motions {role=spec.role,motions=reports.ToArray()})+"\n");
        // A source that delegates standing to VRChat's platform controller has no
        // redistributable idle clip in its archive. Store an explicitly host-owned
        // stationary standing pose, separate from all original motion data.
        for(int i=0;i<rest.Length;i++) {transforms[i].localPosition=rest[i].position;transforms[i].localRotation=rest[i].rotation;transforms[i].localScale=rest[i].scale;}
        if(animator && animator.avatar && animator.avatar.isHuman)
        foreach(bool left in new[]{true,false})
        {
            var upper=animator.GetBoneTransform(left?HumanBodyBones.LeftUpperArm:HumanBodyBones.RightUpperArm);
            var lower=animator.GetBoneTransform(left?HumanBodyBones.LeftLowerArm:HumanBodyBones.RightLowerArm);
            var hand=animator.GetBoneTransform(left?HumanBodyBones.LeftHand:HumanBodyBones.RightHand);
            if(!upper || !lower || !hand)continue;
            float side=Mathf.Sign(root.InverseTransformPoint(upper.position).x);
            Vector3 down=root.TransformDirection(new Vector3(side*.32f,-.94f,.08f)).normalized;
            upper.rotation=Quaternion.FromToRotation(lower.position-upper.position,down)*upper.rotation;
            down=root.TransformDirection(new Vector3(side*.18f,-.98f,.12f)).normalized;
            lower.rotation=Quaternion.FromToRotation(hand.position-lower.position,down)*lower.rotation;
        }
        var standing=transforms.Select((t,i)=>new Node {path=rest[i].path,name=rest[i].name,parent=rest[i].parent,active=rest[i].active,position=t.localPosition,rotation=t.localRotation,scale=t.localScale}).ToArray();
        File.WriteAllText(output+"/host-standing.json",JsonUtility.ToJson(new Report {role=spec.role,nodes=standing},true)+"\n");
    }
}
