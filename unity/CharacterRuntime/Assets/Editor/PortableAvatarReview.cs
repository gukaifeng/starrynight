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
    [Serializable] class Entry {public string role,source,geometry;}
    [Serializable] class Request { public string[] roles;public Entry[] entries;public string outputRoot;public bool reuseImportedMirror; }
    [Serializable] class Node { public string path;public bool active; }
    [Serializable] class Skin { public string path;public bool active,enabled; }
    [Serializable] class Geometry { public Node[] nodes;public Skin[] skins; }
    [Serializable] class Check {public string id,label,kind,context;public bool changed,resetRestored;public float parameter;}
    [Serializable] class Checks {public int schemaVersion=1;public string role,manifestSHA256;public Check[] controls;}
    [Serializable] class MotionChecks {public int schemaVersion=1,strands,colliders,frames,blinkBindings;public string manifestSHA256;public float maximumRotationDegrees,hairTravel,clothTravel;public bool deviceVerified=false;}
    [Serializable] class RenderChecks {public int schemaVersion=1;public string manifestSHA256,assetFolder,defaultSHA256,eyelidsSHA256;public bool nonemptyPixels=true;}
    public static void Run() => RunRequest(".local/vrchat-batch/review-request.json");
    public static void RunModelReview() => RunRequest(".local/vrchat-batch/model-review/review-request.json");
    public static void RenderModelReview() => RunRequest(".local/vrchat-batch/model-review/review-request.json",true);
    static void RunRequest(string requestPath,bool renderOnly=false)
    {
        string root=CharacterPackageBuilder.Root;
        var request=JsonUtility.FromJson<Request>(File.ReadAllText(Path.Combine(root,requestPath)));
        string PrivatePath(string relative) {
            string path=Path.GetFullPath(Path.IsPathRooted(relative)?relative:Path.Combine(root,relative));
            if(!path.StartsWith(Path.Combine(root,".local/vrchat-batch")+Path.DirectorySeparatorChar,StringComparison.Ordinal) &&
               !path.StartsWith(Path.Combine(root,".local/vrchat-stage")+Path.DirectorySeparatorChar,StringComparison.Ordinal))
                throw new Exception("REVIEW_PATH_OUTSIDE_QUARANTINE");
            return path;
        }
        string outputRoot=PrivatePath(string.IsNullOrEmpty(request.outputRoot)?".local/vrchat-batch/render":request.outputRoot);
        Directory.CreateDirectory(outputRoot);
        var entries=request.entries ?? (request.roles??Array.Empty<string>()).Select(role=>{
            string visual=root+"/.local/vrchat-batch/visual/"+role;
            return new Entry {role=role,source=File.Exists(visual+"/character.json")?visual:root+"/.local/vrchat-batch/converted/"+role,
                geometry=root+"/.local/vrchat-batch/stages/"+role+"/Inspection/Portable/"+role+"/geometry.json"};
        }).ToArray();
        // Review the batch in one temporary scene without saving it.
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var c in viewer.characters)c.gameObject.SetActive(false);
        foreach(var entry in entries)
        {
            string role=entry.role;
            if(string.IsNullOrEmpty(role) || role.IndexOfAny(new[]{'/','\\'})>=0 || role.Contains(".."))throw new Exception("REVIEW_ROLE_INVALID");
            string source=PrivatePath(entry.source);
            var selected=JsonUtility.FromJson<CharacterManifest>(File.ReadAllText(source+"/character.json"));
            // This mirror is generated data. Reusing it avoids importing another
            // complete copy of identical textures/meshes into the Editor cache.
            // Author packages and the saved player scene remain unchanged here.
            string folder=(request.entries!=null && !request.reuseImportedMirror?"Assets/CharacterPackages/ModelReview/":"Assets/CharacterPackages/Imported/")+selected.id;
            foreach(string file in renderOnly?Array.Empty<string>():Directory.GetFiles(source,"*",SearchOption.AllDirectories))
            {
                string target=folder+file.Substring(source.Length);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                if(!File.Exists(target) || File.ReadAllBytes(file).SequenceEqual(File.ReadAllBytes(target))==false)File.Copy(file,target,true);
            }
            if(!renderOnly) {
                AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
                var importer=AssetImporter.GetAtPath(folder+"/model.glb");
                var settings=new SerializedObject(importer);var method=settings.FindProperty("importSettings.animationMethod");
                int legacy=Array.IndexOf(method.enumNames,"Legacy");
                if(method.enumValueIndex!=legacy) {method.enumValueIndex=legacy;settings.ApplyModifiedPropertiesWithoutUndo();importer.SaveAndReimport();}
            }
            // Rendering an activated package uses the saved production scene.
            // It must not rebuild/import assets between camera requests.
            var prepared=renderOnly?viewer.characters.Single(c=>c.modelId==selected.id):null;
            if(prepared && prepared.contractAsset.text!=File.ReadAllText(source+"/character.json"))throw new Exception("REVIEW_SCENE_CONTRACT_STALE");
            var model=prepared?prepared.gameObject:UnityEngine.Object.Instantiate(AssetDatabase.LoadAssetAtPath<GameObject>(folder+"/model.glb"));
            model.SetActive(true);
            var clips=AssetDatabase.LoadAllAssetsAtPath(folder+"/model.glb").OfType<AnimationClip>();
            var idle=clips.First(c=>c.name=="Idle");idle.SampleAnimation(model,0);
            var geometry=JsonUtility.FromJson<Geometry>(File.ReadAllText(PrivatePath(entry.geometry)));
            foreach(var n in geometry.nodes) {var t=model.transform.Find("Avatar"+(n.path==""?"":"/"+n.path));if(t)t.gameObject.SetActive(n.active);}
            foreach(var s in geometry.skins) {var t=model.transform.Find("Avatar/"+s.path);if(t && t.TryGetComponent<Renderer>(out var renderer))renderer.enabled=s.enabled;}
            var reviewCharacter=model.GetComponent<ViewerCharacter>() ?? model.AddComponent<ViewerCharacter>();
            reviewCharacter.contractAsset=AssetDatabase.LoadAssetAtPath<TextAsset>(folder+"/character.json");
            if(!renderOnly) {
                AnimeCharacterAdapter.PrepareMaterials(reviewCharacter,folder);
                PortableAvatarControllerBuilder.Prepare(model,folder,clips.First(c=>c.name=="Idle"));
            }
            var driver=model.GetComponent<AvatarControlDriver>();
            if(driver && !renderOnly)
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
                string checkPath=Path.Combine(outputRoot,role+"-controls.json");
                using(var hash=System.Security.Cryptography.SHA256.Create())
                    File.WriteAllText(checkPath,JsonUtility.ToJson(new Checks {role=role,
                        manifestSHA256=BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(source+"/character.json"))).Replace("-","").ToLowerInvariant(),
                        controls=checks.ToArray()},true));
            }
            var motion=AnimeCharacterAdapter.PrepareSecondary(model,folder);
            var motionChecks=new MotionChecks {strands=motion.strands.Length,colliders=motion.colliders.Length,
                frames=240,blinkBindings=selected.autonomy?.blink?.bindings?.Length??0};
            var originalRotation=model.transform.localRotation;
            for(int frame=0;!renderOnly && frame<motionChecks.frames;frame++)
            {
                motion.RestorePose();
                if(driver)driver.animator.Update(1f/60);
                else idle.SampleAnimation(model,(frame/60f)%Mathf.Max(idle.length,.0001f));
                model.transform.localRotation=originalRotation*Quaternion.Euler(0,12*Mathf.Sin(frame/60f),0);
                var before=motion.strands.Select(s=>s.bone.localRotation).ToArray();
                motion.Step(1f/60);
                for(int i=0;i<before.Length;i++)motionChecks.maximumRotationDegrees=Mathf.Max(motionChecks.maximumRotationDegrees,
                    CharacterAutonomy.MotionAngle(before[i],motion.strands[i].bone.localRotation));
            }
            motionChecks.hairTravel=motion.HairTravel;motionChecks.clothTravel=motion.ClothTravel;
            if(!renderOnly && motionChecks.strands>0 && motionChecks.maximumRotationDegrees<=.00001f)throw new Exception("REVIEW_SECONDARY_MOTION_FROZEN");
            motion.RestorePose();model.transform.localRotation=originalRotation;motion.ResetSimulation();
            using(var hash=System.Security.Cryptography.SHA256.Create())motionChecks.manifestSHA256=
                BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(source+"/character.json"))).Replace("-","").ToLowerInvariant();
            var renderers=model.GetComponentsInChildren<Renderer>().Where(r=>r.enabled).ToArray();
            var bounds=renderers[0].bounds;foreach(var r in renderers.Skip(1))bounds.Encapsulate(r.bounds);
            var camera=viewer.viewCamera;camera.aspect=.75f;
            var focus=bounds.center+Vector3.up*bounds.size.y*.12f;
            camera.transform.position=focus+Vector3.forward*Mathf.Max(bounds.size.y*1.3f,bounds.size.x*1.4f);camera.transform.LookAt(focus);
            string output=Path.Combine(outputRoot,role+".png");
            PortraitRefinementReview.Render(camera,output,720,960);PortraitRefinementReview.Render(camera,output,720,960);
            var manifest=JsonUtility.FromJson<CharacterManifest>(File.ReadAllText(source+"/character.json"));
            if(manifest.autonomy?.blink?.bindings?.Length>0) {
                var snapshots=new System.Collections.Generic.List<GameObject>();
                foreach(var group in manifest.autonomy.blink.bindings.GroupBy(b=>b.renderer)) {
                    var skin=model.transform.Find(group.Key)?.GetComponent<SkinnedMeshRenderer>();
                    if(!skin)throw new Exception("REVIEW_BLINK_RENDERER_MISSING");
                    foreach(var binding in group) {
                        int shape=skin.sharedMesh.GetBlendShapeIndex(binding.shape);
                        if(shape<0)throw new Exception("REVIEW_BLINK_BINDING_MISSING");
                        skin.SetBlendShapeWeight(shape,CharacterContract.MorphScale(skin,shape)*binding.weight);
                    }
                    // Editor Camera.Render can reuse the GPU skin buffer within
                    // the same frame. Bake the current explicit weight so this
                    // evidence actually shows the requested closed-eyelid pose.
                    var snapshot=new GameObject("Eyelid review snapshot");snapshot.transform.SetParent(skin.transform,false);
                    var mesh=new Mesh();skin.BakeMesh(mesh);snapshot.AddComponent<MeshFilter>().sharedMesh=mesh;
                    snapshot.AddComponent<MeshRenderer>().sharedMaterials=skin.sharedMaterials;skin.enabled=false;snapshots.Add(snapshot);
                }
                PortraitRefinementReview.Render(camera,Path.Combine(outputRoot,role+"-eyelids.png"),720,960);
                foreach(var snapshot in snapshots){UnityEngine.Object.DestroyImmediate(snapshot.GetComponent<MeshFilter>().sharedMesh);UnityEngine.Object.DestroyImmediate(snapshot);}
            }
            string motionPath=Path.Combine(outputRoot,role+"-motion.json");
            if(renderOnly) {
                var prior=JsonUtility.FromJson<MotionChecks>(File.ReadAllText(motionPath));
                if(prior.manifestSHA256!=motionChecks.manifestSHA256 || prior.frames<240)throw new Exception("REVIEW_PRIOR_MOTION_REQUIRED");
            } else File.WriteAllText(motionPath,JsonUtility.ToJson(motionChecks,true));
            string HashFile(string path) {
                using(var hash=System.Security.Cryptography.SHA256.Create())
                    return BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(path))).Replace("-","").ToLowerInvariant();
            }
            File.WriteAllText(Path.Combine(outputRoot,role+"-render.json"),JsonUtility.ToJson(new RenderChecks {
                manifestSHA256=motionChecks.manifestSHA256,assetFolder=folder,defaultSHA256=HashFile(output),
                eyelidsSHA256=HashFile(Path.Combine(outputRoot,role+"-eyelids.png"))},true));
            Debug.Log("PORTABLE_AVATAR_RENDERED "+role+" bounds="+bounds+" renderers="+renderers.Length);
            if(renderOnly)model.SetActive(false);
            else UnityEngine.Object.DestroyImmediate(model);
        }
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        AssetDatabase.SaveAssets();
    }
}
