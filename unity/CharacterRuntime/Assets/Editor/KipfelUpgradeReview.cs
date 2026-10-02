using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEngine;
using UnityEngine.Animations;

public static class KipfelUpgradeReview
{
    public static void ReviewAndCapture() {Run();CharacterPerformanceReview.RunAndCapture();CharacterCoverBuilder.Export();}
    public static void BuildAndReview() {BuildIos.Setup();ReviewAndCapture();}
    public static void ReviewAndExportDevice() {ReviewAndCapture();BuildIos.ExportPreparedDevice();}
    public static void RefreshThumbnail()
    {
        BuildIos.ThumbnailCharacter("anime-kipfel","garden");
        // Capture framing adjusts the shared shadow range while reviewing.
        // Keep its ordinary tracked default after disposable editor captures.
        var pipeline=UnityEditor.AssetDatabase.LoadAssetAtPath<UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset>("Assets/Settings/Mobile_RPAsset.asset");
        pipeline.shadowDistance=18;
        UnityEditor.EditorUtility.SetDirty(pipeline);UnityEditor.AssetDatabase.SaveAssetIfDirty(pipeline);
    }
    static int checks;
    static void Check(bool value,string detail)
    {
        checks++;if(!value)throw new Exception("KIPFEL_UPGRADE_FAILED: "+detail);
    }
    public static void Run()
    {
        checks=0;BuildIos.Validate();
        var all=UnityEngine.Object.FindObjectsByType<ViewerCharacter>(FindObjectsInactive.Include,FindObjectsSortMode.None);
        Check(all.All(c=>c.modelId!="anime-kipfel-v111"),"duplicate preview is retired");
        var source=all.Single(c=>c.modelId=="anime-kipfel");
        var clone=UnityEngine.Object.Instantiate(source.gameObject);
        clone.SetActive(true);
        var actor=clone.GetComponent<ViewerCharacter>();actor.ApplyContract();
        var host=new GameObject("KipfelUpgradeTestHost");
        try
        {
            Check(actor.Manifest.display.originalName.Contains("1.1.1"),"new author version");
            Check(actor.Manifest.display.name=="小猫","display identity");
            Check(actor.Manifest.speech.mode=="amplitude","speech retained");
            Check(actor.Manifest.performance.options.Length==87,"author presentations and PetMode choices");
            Check(actor.Manifest.performance.groups.Length==7,"all presentation groups");
            Check(clone.GetComponentsInChildren<SkinnedMeshRenderer>(true).Sum(s=>s.sharedMesh.blendShapeCount)==456,"all source morph channels retained");
            var constraints=clone.GetComponentsInChildren<RotationConstraint>(true);
            Check(constraints.Length==5 && constraints.All(c=>c.constraintActive && c.sourceCount==1 && c.GetSource(0).sourceTransform),"five bound rotation constraints");
            var physics=clone.GetComponent<AvatarSecondaryMotion>();
            Check(physics && physics.strands.Length==105 && physics.planes.Length==5,"hair/cloth including optional cuffs and plane bindings");
            Check(physics.strands.All(s=>s.colliderIDs!=null),"collision associations explicit");
            var driver=host.AddComponent<CharacterPerformanceDriver>();driver.Bind(actor);
            void Settle() {for(int i=0;i<60;i++){driver.Step(1f/60);driver.RestoreMorphs();driver.ApplyFrame();}}
            var cuffs=physics.strands.Where(s=>s.bone.name.StartsWith("Sleeve.",StringComparison.Ordinal)).ToArray();
            Check(cuffs.Length==2 && cuffs.All(s=>!s.enabled),"author default cuff physics disabled");
            driver.Select("outfit-shirt-sleeve",1);Settle();
            Check(cuffs.All(s=>s.enabled),"short sleeve enables its physical cuffs");
            cuffs[0].velocity=Vector3.right;driver.ApplyFrame();
            Check(cuffs[0].velocity==Vector3.right,"unchanged control does not restart spring each frame");
            driver.Select("outfit-shirt-sleeve",0);Settle();
            Check(cuffs.All(s=>!s.enabled),"long sleeve disables separate cuff solver");
            string lowerLeg=physics.controls.Single(c=>c.option=="kipfel-cattail-roll").on[0].id;
            driver.Select("kipfel-cattail-roll",1);Settle();
            Check(physics.colliders.Where(c=>c.id==lowerLeg).All(c=>!c.enabled),"rolled tail disables authored lower-leg collisions");
            driver.Reset("tail");Settle();
            Check(physics.colliders.Where(c=>c.id==lowerLeg).All(c=>c.enabled),"tail reset restores collision state");
            var pet=clone.GetComponent<CharacterPetFeedback>();
            Check(pet && pet.Mode==1,"authored default happy PetMode");
            Check(driver.Select("kipfel-facial-catsmile",1)==null,"manual expression");
            Check(pet.Tap(driver) && driver.Selections.Contains("kipfel-facial-happy"),"head contact selects author happy face");
            pet.Restore();
            Check(driver.Selections.Contains("kipfel-facial-catsmile"),"pet restores previous expression");
            Check(driver.Select("pet-mode-unhappy",1)==null && pet.Mode==2,"unhappy mode");
            Check(pet.Tap(driver) && driver.Selections.Contains("kipfel-facial-unhappy"),"unhappy reaction");
            Check(driver.Select("kipfel-facial-catsmile",1)==null && driver.Selections.Contains("kipfel-facial-catsmile"),"manual choice overrides active pet reaction");
            Check(driver.Select("pet-mode-off",1)==null && !pet.Tap(driver),"disabled mode does not react");
            Check(driver.Reset("interaction")==null && pet.Mode==1,"interaction default restored");
            driver.Clear();
            ReviewPlane();
            string output=Path.GetFullPath("../../.local/kipfel-upgrade/runtime-review.json");
            File.WriteAllText(output,"{\"checks\":"+checks+",\"status\":\"PASS\",\"sourceVersion\":\"1.1.1\",\"devicePerformanceMeasured\":false}\n");
            Debug.Log("KIPFEL_UPGRADE_REVIEW_PASS checks="+checks);
        }
        finally {UnityEngine.Object.DestroyImmediate(host);UnityEngine.Object.DestroyImmediate(clone);}
    }
    static void ReviewPlane()
    {
        var root=new GameObject("ScopedPlaneTest");
        try
        {
            var bone=new GameObject("strand").transform;bone.SetParent(root.transform,false);
            var tip=new GameObject("tip").transform;tip.SetParent(bone,false);tip.localPosition=Vector3.right;
            var strand=new AvatarSecondaryMotion.Strand {bone=bone,tip=tip,radius=.01f,angle=20,wind="none",colliderIDs=new[]{"other"}};
            var solver=root.AddComponent<AvatarSecondaryMotion>();solver.ambientHairAngle=0;solver.ambientClothAngle=0;
            solver.strands=new[]{strand};solver.planes=new[]{new AvatarSecondaryMotion.Plane {bone=root.transform,id="floor",normal=Vector3.up}};
            solver.Step(1f/60);
            Check(Mathf.Abs(tip.position.y)<.00001f,"unassociated plane does not affect strand");
            strand.colliderIDs=new[]{"floor"};solver.ResetSimulation();solver.Step(1f/60);
            Check(tip.position.y>=.0099f && tip.position.y<.02f,"associated plane resolves skin radius without extreme bend");
        }
        finally {UnityEngine.Object.DestroyImmediate(root);}
    }
}
