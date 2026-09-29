using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
public static class VrcSourceInspector {
 [Serializable] public class Report {public string role,fbx,prefab;public Node[] nodes;public Skin[] skins;public Bone[] human;public bool humanValid;public Missing[] missing;}
 [Serializable] public class Node {public string path,name;public long sourceID;public string sourceGUID;public bool active;public Vector3 position,scale;public Quaternion rotation;}
 [Serializable] public class Skin {public string path,name;public bool active,enabled;public string mesh;public int vertices,triangles;public string[] materials,materialGUIDs,shapes,bones;public float[] weights;}
 [Serializable] public class Bone {public string human,path;}
 [Serializable] public class Missing {public string path;public int count;}
 static string PathOf(Transform t,Transform root) {return t==root?"":AnimationUtility.CalculateTransformPath(t,root);}
 [Serializable] public class Specs {public Spec[] specs;}
 [Serializable] public class Spec {public string role,fbx,prefab;}
 public static void Export(){
  Directory.CreateDirectory("Inspection");
  var config=JsonUtility.FromJson<Specs>(File.ReadAllText("InspectionConfig.json"));
  foreach(var spec in config.specs){
   var fbxImporter=(ModelImporter)AssetImporter.GetAtPath(spec.fbx);fbxImporter.isReadable=true;fbxImporter.SaveAndReimport();
   foreach(bool original in new[]{true,false}){
    var asset=AssetDatabase.LoadAssetAtPath<GameObject>(original?spec.fbx:spec.prefab);if(!asset)throw new Exception("Missing asset:"+spec.fbx);
    var go=(GameObject)PrefabUtility.InstantiatePrefab(asset);var root=go.transform;var animator=go.GetComponent<Animator>();
    if(animator)animator.enabled=false;
    var report=new Report{role=spec.role,fbx=spec.fbx,prefab=original?null:spec.prefab,humanValid=animator && animator.avatar && animator.avatar.isValid && animator.avatar.isHuman};
    report.nodes=root.GetComponentsInChildren<Transform>(true).Select(t=>{
     var source=PrefabUtility.GetCorrespondingObjectFromSource(t); string guid="";long id=0;
     if(source)AssetDatabase.TryGetGUIDAndLocalFileIdentifier(source,out guid,out id);
     return new Node{path=PathOf(t,root),name=t.name,sourceID=id,sourceGUID=guid,active=t.gameObject.activeInHierarchy,position=t.localPosition,rotation=t.localRotation,scale=t.localScale};
    }).ToArray();
    report.skins=go.GetComponentsInChildren<SkinnedMeshRenderer>(true).Select(s=>new Skin{path=PathOf(s.transform,root),name=s.name,active=s.gameObject.activeInHierarchy,enabled=s.enabled,mesh=s.sharedMesh.name,vertices=s.sharedMesh.vertexCount,triangles=s.sharedMesh.triangles.Length/3,materials=s.sharedMaterials.Select(m=>m?m.name:"").ToArray(),materialGUIDs=s.sharedMaterials.Select(m=>m?AssetDatabase.AssetPathToGUID(AssetDatabase.GetAssetPath(m)):"").ToArray(),shapes=Enumerable.Range(0,s.sharedMesh.blendShapeCount).Select(i=>s.sharedMesh.GetBlendShapeName(i)).ToArray(),weights=Enumerable.Range(0,s.sharedMesh.blendShapeCount).Select(s.GetBlendShapeWeight).ToArray(),bones=s.bones.Select(t=>PathOf(t,root)).ToArray()}).ToArray();
    var human=new List<Bone>();if(report.humanValid)foreach(HumanBodyBones b in Enum.GetValues(typeof(HumanBodyBones)))if(b!=HumanBodyBones.LastBone){var t=animator.GetBoneTransform(b);if(t)human.Add(new Bone{human=b.ToString(),path=PathOf(t,root)});};report.human=human.ToArray();
    report.missing=root.GetComponentsInChildren<Transform>(true).Select(t=>new Missing{path=PathOf(t,root),count=GameObjectUtility.GetMonoBehavioursWithMissingScriptCount(t.gameObject)}).Where(x=>x.count>0).ToArray();
    File.WriteAllText("Inspection/"+spec.role+(original?"-fbx":"-prefab")+".json",JsonUtility.ToJson(report,true)+"\n");
    Debug.Log("VRC_SOURCE_INSPECTED "+spec.role+" original="+original+" human="+report.humanValid+" skins="+report.skins.Length);
    UnityEngine.Object.DestroyImmediate(go);
   }
  }
 }
}
