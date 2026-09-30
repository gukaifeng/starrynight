using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using ModelSpace;

// Quarantine rendering never changes the release roster or saved player scene.
public static class PortableAvatarReview
{
    [Serializable] class Request { public string[] roles; }
    [Serializable] class Node { public string path;public bool active; }
    [Serializable] class Skin { public string path;public bool active,enabled; }
    [Serializable] class Geometry { public Node[] nodes;public Skin[] skins; }
    [Serializable] class Check {public string id,label,kind,context;public bool changed,resetRestored;public float parameter;}
    [Serializable] class Checks {public int schemaVersion=1;public string role,manifestSHA256;public Check[] controls;}
    public static void Run()
    {
        string root=CharacterPackageBuilder.Root;
        var request=JsonUtility.FromJson<Request>(File.ReadAllText(root+"/.local/vrchat-batch/review-request.json"));
        foreach(string role in request.roles)
        {
            string source=root+"/.local/vrchat-batch/converted/"+role;
            string folder="Assets/CharacterPackages/Imported/anime-"+role;
            foreach(string file in Directory.GetFiles(source,"*",SearchOption.AllDirectories))
            {
                string target=folder+file.Substring(source.Length);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                if(!File.Exists(target) || File.ReadAllBytes(file).SequenceEqual(File.ReadAllBytes(target))==false)File.Copy(file,target,true);
            }
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            var importer=AssetImporter.GetAtPath(folder+"/model.glb");
            var settings=new SerializedObject(importer);var method=settings.FindProperty("importSettings.animationMethod");
            int legacy=Array.IndexOf(method.enumNames,"Legacy");
            if(method.enumValueIndex!=legacy) {method.enumValueIndex=legacy;settings.ApplyModifiedPropertiesWithoutUndo();importer.SaveAndReimport();}
            EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
            var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
            foreach(var c in viewer.characters)c.gameObject.SetActive(false);
            var model=UnityEngine.Object.Instantiate(AssetDatabase.LoadAssetAtPath<GameObject>(folder+"/model.glb"));
            var clips=AssetDatabase.LoadAllAssetsAtPath(folder+"/model.glb").OfType<AnimationClip>();
            clips.First(c=>c.name=="Idle").SampleAnimation(model,0);
            var geometry=JsonUtility.FromJson<Geometry>(File.ReadAllText(root+"/.local/vrchat-batch/stages/"+role+"/Inspection/Portable/"+role+"/geometry.json"));
            foreach(var n in geometry.nodes) {var t=model.transform.Find("Avatar"+(n.path==""?"":"/"+n.path));if(t)t.gameObject.SetActive(n.active);}
            foreach(var s in geometry.skins) {var t=model.transform.Find("Avatar/"+s.path);if(t)t.GetComponent<Renderer>().enabled=s.enabled;}
            PortableToonMaterialBuilder.Prepare(model,folder);
            PortableAvatarControllerBuilder.Prepare(model,folder,clips.First(c=>c.name=="Idle"));
            var driver=model.GetComponent<AvatarControlDriver>();
            if(driver)
            {
                string Snapshot() {
                    var parts=new System.Collections.Generic.List<string>();
                    foreach(var t in model.GetComponentsInChildren<Transform>(true))parts.Add(t.name+":"+t.gameObject.activeSelf+":"+t.localPosition.ToString("F4")+":"+t.localRotation.ToString("F4"));
                    foreach(var s in model.GetComponentsInChildren<SkinnedMeshRenderer>(true)) {
                        parts.Add(s.name+":"+s.enabled+":"+string.Join(",",s.sharedMaterials.Select(m=>m?m.name:"null")));
                        for(int i=0;i<s.sharedMesh.blendShapeCount;i++)parts.Add(s.GetBlendShapeWeight(i).ToString("F3"));
                    }
                    foreach(var r in model.GetComponentsInChildren<Renderer>(true)) {
                        var block=new MaterialPropertyBlock();r.GetPropertyBlock(block);
                        foreach(var m in r.sharedMaterials.Where(m=>m && m.shader))
                            for(int p=0;p<m.shader.GetPropertyCount();p++) {
                                int id=m.shader.GetPropertyNameId(p);var type=m.shader.GetPropertyType(p);
                                if(type==UnityEngine.Rendering.ShaderPropertyType.Float || type==UnityEngine.Rendering.ShaderPropertyType.Range)
                                    parts.Add(m.GetFloat(id).ToString("F4")+":"+block.GetFloat(id).ToString("F4"));
                                else if(type==UnityEngine.Rendering.ShaderPropertyType.Color || type==UnityEngine.Rendering.ShaderPropertyType.Vector)
                                    parts.Add(m.GetVector(id).ToString("F4")+":"+block.GetVector(id).ToString("F4"));
                            }
                    }
                    for(int layer=0;layer<driver.animator.layerCount;layer++)parts.Add("weight:"+driver.animator.GetLayerWeight(layer).ToString("F4"));
                    parts.Add("tracking:"+driver.AllowBlink+":"+driver.AllowSpeech);
                    return string.Join("|",parts);
                }
                var checks=new System.Collections.Generic.List<Check>();
                foreach(var control in driver.profile.controls)
                {
                    driver.Reset();for(int i=0;i<60;i++)driver.animator.Update(1f/60);
                    string before=Snapshot();float value=control.kind=="slider"?.8f:Mathf.Abs(driver.Get(control.parameter)-control.value)<.001f?0:1;
                    if(driver.Select(control.id,value)!=null)throw new Exception("PORTABLE_CONTROL_REJECTED: "+control.id);
                    bool changed=false;
                    for(int i=0;i<120;i++) {
                        driver.AdvanceWeights(1f/60);driver.animator.Update(1f/60);
                        if(i%20==0 || i==119)changed|=before!=Snapshot();
                    }
                    var check=new Check {id=control.id,label=control.label,kind=control.kind,changed=changed,parameter=driver.Get(control.parameter)};
                    // Expression-bank and expression-lock controls can have no
                    // visual effect in neutral. Exercise them while author hand
                    // expressions are active; a neutral-only sample is insufficient.
                    if(!changed && Math.Abs(control.value-control.initial)>.001f && control.kind!="slider")
                    {
                        foreach(var gesture in driver.profile.controls.Where(c=>c.parameter.StartsWith("Gesture",StringComparison.Ordinal) && c.value>0)) {
                            driver.Reset();driver.Select(gesture.id,1);
                            for(int i=0;i<60;i++){driver.AdvanceWeights(1f/60);driver.animator.Update(1f/60);}
                            string contextual=Snapshot();driver.Select(control.id,1);
                            for(int i=0;i<60;i++){driver.AdvanceWeights(1f/60);driver.animator.Update(1f/60);}
                            // A lock acts on the next change, not on the current pose.
                            driver.Select(gesture.id,0);
                            for(int i=0;i<60;i++){driver.AdvanceWeights(1f/60);driver.animator.Update(1f/60);}
                            string actual=Snapshot();
                            driver.Reset();driver.Select(gesture.id,1);
                            for(int i=0;i<60;i++){driver.AdvanceWeights(1f/60);driver.animator.Update(1f/60);}
                            driver.Select(gesture.id,0);
                            for(int i=0;i<60;i++){driver.AdvanceWeights(1f/60);driver.animator.Update(1f/60);}
                            if(actual!=Snapshot()) {check.changed=true;check.context=gesture.id+" followed by release";break;}
                            // A bank switch is visible before releasing the hand.
                            driver.Reset();driver.Select(gesture.id,1);driver.Select(control.id,1);
                            for(int i=0;i<60;i++){driver.AdvanceWeights(1f/60);driver.animator.Update(1f/60);}
                            if(contextual!=Snapshot()){check.changed=true;check.context=gesture.id;break;}
                        }
                    }
                    driver.Reset();for(int i=0;i<60;i++)driver.animator.Update(1f/60);
                    check.resetRestored=before==Snapshot();checks.Add(check);
                    if(!check.resetRestored)throw new Exception("PORTABLE_RESET_FAILED: "+control.id);
                }
                driver.Reset();
                string checkPath=root+"/.local/vrchat-batch/render/"+role+"-controls.json";Directory.CreateDirectory(Path.GetDirectoryName(checkPath));
                using(var hash=System.Security.Cryptography.SHA256.Create())
                    File.WriteAllText(checkPath,JsonUtility.ToJson(new Checks {role=role,
                        manifestSHA256=BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(source+"/character.json"))).Replace("-","").ToLowerInvariant(),
                        controls=checks.ToArray()},true));
            }
            var renderers=model.GetComponentsInChildren<Renderer>().Where(r=>r.enabled).ToArray();
            var bounds=renderers[0].bounds;foreach(var r in renderers.Skip(1))bounds.Encapsulate(r.bounds);
            var camera=viewer.viewCamera;camera.aspect=.75f;
            var focus=bounds.center+Vector3.up*bounds.size.y*.12f;
            camera.transform.position=focus+Vector3.forward*Mathf.Max(bounds.size.y*1.3f,bounds.size.x*1.4f);camera.transform.LookAt(focus);
            string output=root+"/.local/vrchat-batch/render/"+role+".png";Directory.CreateDirectory(Path.GetDirectoryName(output));
            PortraitRefinementReview.Render(camera,output,720,960);PortraitRefinementReview.Render(camera,output,720,960);
            var manifest=JsonUtility.FromJson<CharacterManifest>(File.ReadAllText(source+"/character.json"));
            if(manifest.autonomy?.blink?.bindings?.Length>0) {
                var snapshots=new System.Collections.Generic.List<GameObject>();
                foreach(var binding in manifest.autonomy.blink.bindings) {
                    var skin=model.transform.Find(binding.renderer).GetComponent<SkinnedMeshRenderer>();
                    int shape=skin.sharedMesh.GetBlendShapeIndex(binding.shape);
                    if(shape<0)throw new Exception("REVIEW_BLINK_BINDING_MISSING");
                    skin.SetBlendShapeWeight(shape,CharacterContract.MorphScale(skin,shape)*binding.weight);
                    // Editor Camera.Render can reuse the GPU skin buffer within
                    // the same frame. Bake the current explicit weight so this
                    // evidence actually shows the requested closed-eyelid pose.
                    var snapshot=new GameObject("Eyelid review snapshot");snapshot.transform.SetParent(skin.transform,false);
                    var mesh=new Mesh();skin.BakeMesh(mesh);snapshot.AddComponent<MeshFilter>().sharedMesh=mesh;
                    snapshot.AddComponent<MeshRenderer>().sharedMaterials=skin.sharedMaterials;skin.enabled=false;snapshots.Add(snapshot);
                }
                PortraitRefinementReview.Render(camera,root+"/.local/vrchat-batch/render/"+role+"-eyelids.png",720,960);
                foreach(var snapshot in snapshots){UnityEngine.Object.DestroyImmediate(snapshot.GetComponent<MeshFilter>().sharedMesh);UnityEngine.Object.DestroyImmediate(snapshot);}
            }
            Debug.Log("PORTABLE_AVATAR_RENDERED "+role+" bounds="+bounds+" renderers="+renderers.Length);
        }
        AssetDatabase.SaveAssets();
    }
}
