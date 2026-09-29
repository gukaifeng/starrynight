using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;

// Exercises the actual imported clips, morph geometry and constrained solver.
// Separate live-app checks cover Unity's automatic Update/animation/LateUpdate.
public static class NaturalIdleReview
{
    [Serializable] sealed class Row
    {
        public string id; public int hz,blinks,staticPoses;
        public float blinkPeak,closedMeshDelta,headTravel,chestTravel,hairTravel,clothTravel,maxWindAngle;
        public float blinkDuration,sourceHeadRange,headRange,sourceChestRange,chestRange;
        public bool speechPreserved,expressionPriority,sleepPriority,rebindRestored,windWithoutBodyMotion;
    }
    [Serializable] sealed class Report
    {
        public string status="PASS",scope="Imported morphs, source breathing, static-pose layering, expression/sleep priority, inactive actors, finite constrained wind at 60/120 Hz. Simulation rates are not device FPS measurements.";
        public int assertions;
        public List<Row> characters=new List<Row>();
    }
    static Report report;
    static string Output=>Path.Combine(CharacterPackageBuilder.Root,"docs/verification/idle-refinement");
    static void Check(bool ok,string reason){if(!ok)throw new Exception("NATURAL_IDLE_REVIEW: "+reason);report.assertions++;}
    public static void BuildAndReview(){BuildIos.Setup();BuildIos.Validate();Run();}
    public static void ReviewAndExportSimulator(){BuildAndReview();BuildIos.ExportPreparedSimulator();}
    public static void DiagnoseWind()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var c=viewer.characters.Single(x=>x.modelId=="anime-mamehinata");c.gameObject.SetActive(true);
        c.GetComponent<Animation>().GetClip("Idle").SampleAnimation(c.gameObject,0);
        var wind=c.GetComponent<AvatarSecondaryMotion>();wind.ResetSimulation();
        for(int i=0;i<600;i++){wind.RestorePose();wind.Step(1f/60);}
        Debug.Log("WIND_DIAG angles="+wind.ambientHairAngle+","+wind.ambientClothAngle+" travel="+wind.HairTravel+","+wind.ClothTravel);
        foreach(var s in wind.strands.Where(s=>s.wind=="hair"))Debug.Log("WIND_STRAND "+s.bone.name+" len="+Vector3.Distance(s.bone.position,s.tip.position)+" velocity="+s.velocity.ToString("F7")+" angle="+CharacterAutonomy.MotionAngle(s.animatedRotation,s.bone.localRotation)+" response="+s.windResponse);
    }
    public static void Run()
    {
        report=new Report();Directory.CreateDirectory(Output);
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var actor in viewer.characters)actor.gameObject.SetActive(false);
        foreach(var source in viewer.characters)foreach(int hz in new[]{60,120})
        {
            var c=UnityEngine.Object.Instantiate(source);c.name=source.name;c.gameObject.SetActive(true);c.ApplyContract();
            var host=new GameObject("NaturalIdleReviewHost");
            var actions=host.AddComponent<CharacterActions>();var perf=host.AddComponent<CharacterPerformanceDriver>();var auto=host.AddComponent<CharacterAutonomy>();
            var row=new Row {id=c.modelId,hz=hz};report.characters.Add(row);
            var wind=c.GetComponent<AvatarSecondaryMotion>();
            try
            {
                actions.Initialize(c.transform,viewer.viewCamera,null);perf.Bind(c);auto.Bind(c,perf,745);
                var anim=c.GetComponent<Animation>();var idle=anim["Idle"];
                CheckVisibleAmplitude(c,anim,row);
                row.blinkDuration=auto.State.blinkDurationSeconds;
                Check(row.blinkDuration>.44f && row.blinkDuration<.47f,c.modelId+" slower individual blink, unchanged interval schedule");
                var lid=c.Manifest.autonomy.blink.bindings[0];var skin=CharacterContract.Resolve(c.transform,lid.renderer).GetComponent<SkinnedMeshRenderer>();
                int index=skin.sharedMesh.GetBlendShapeIndex(lid.shape);float scale=CharacterContract.MorphScale(skin,index);
                Check(scale>0,c.modelId+" usable original eyelid scale");
                var a=new Mesh();var b=new Mesh();skin.SetBlendShapeWeight(index,0);skin.BakeMesh(a);skin.SetBlendShapeWeight(index,scale);skin.BakeMesh(b);
                var av=a.vertices;var bv=b.vertices;
                row.closedMeshDelta=av.Select((v,i)=>Vector3.Distance(v,bv[i])).Max();
                Check(row.closedMeshDelta>.001f,c.modelId+" closure really deforms the imported eye vertices");
                skin.SetBlendShapeWeight(index,0);UnityEngine.Object.DestroyImmediate(a);UnityEngine.Object.DestroyImmediate(b);
                void Frame(float dt)
                {
                    auto.RestoreMorphs();perf.RestoreMorphs();wind.RestorePose();
                    foreach(AnimationState s in anim)if(s.enabled)s.time+=dt;
                    perf.Step(dt);auto.Step(dt);anim.Sample();perf.ApplyFrame();auto.ApplyFrame();wind.Step(dt);
                    Check(float.IsFinite(auto.State.headMotionDegrees),c.modelId+" finite breath");
                    foreach(var strand in wind.strands)
                    {
                        float angle=CharacterAutonomy.MotionAngle(strand.animatedRotation,strand.bone.localRotation);
                        row.maxWindAngle=Mathf.Max(row.maxWindAngle,angle);
                        Check(float.IsFinite(strand.point.sqrMagnitude) && angle<=strand.angle+.12f,c.modelId+" finite bounded spring "+strand.bone.name);
                    }
                }
                for(int frame=0;frame<hz*24;frame++)
                {
                    Frame(1f/hz);row.blinkPeak=Mathf.Max(row.blinkPeak,skin.GetBlendShapeWeight(index)/scale);
                    if(hz==60 && frame==hz)Capture(c,viewer,"open");
                    if(hz==60 && skin.GetBlendShapeWeight(index)/scale>.97f && !File.Exists(Path.Combine(Output,c.modelId+"-blink.png")))Capture(c,viewer,"blink");
                }
                row.blinks=auto.State.blinkCount;row.headTravel=auto.State.headMotionDegrees;row.chestTravel=auto.State.chestMotionDegrees;
                row.hairTravel=wind.HairTravel;row.clothTravel=wind.ClothTravel;
                Check(row.blinks>=3 && row.blinkPeak>.92f,c.modelId+" autonomous irregular blink cycles");
                Check(row.headTravel>.4f && row.chestTravel>.4f,c.modelId+" final sampled bones breathe");
                Check(row.hairTravel>.01f && row.clothTravel>.001f,c.modelId+" hair and cloth move without user input");
                Check(auto.State.poseBreathWeight==0,c.modelId+" neutral never doubles source breath");
                // An unrelated original mouth viseme must survive a complete blink.
                var mouth=c.Manifest.speech.amplitude[0];int mi=skin.sharedMesh.GetBlendShapeIndex(mouth.shape);
                skin.SetBlendShapeWeight(mi,.42f*CharacterContract.MorphScale(skin,mi));
                for(int i=0;i<hz*3;i++)Frame(1f/hz);
                row.speechPreserved=Mathf.Abs(skin.GetBlendShapeWeight(mi)/CharacterContract.MorphScale(skin,mi)-.42f)<.001f;
                Check(row.speechPreserved,c.modelId+" blink does not overwrite speech");
                var poseForReset=c.Manifest.autonomy.breathing.poseOptions.First();perf.Select(poseForReset,1);
                var expression=c.Manifest.performance.options.First(o=>o.group=="expression");perf.Select(expression.id,1);
                for(int i=0;i<hz;i++)Frame(1f/hz);
                int count=auto.State.blinkCount;
                for(int i=0;i<hz*12;i++)Frame(1f/hz);
                row.expressionPriority=auto.State.blinkSuppressed && auto.State.blinkWeight==0 && auto.State.blinkCount==count;
                Check(row.expressionPriority,c.modelId+" author expression owns eyelids");perf.Reset("expression");
                Check(perf.Selections.Contains(poseForReset),c.modelId+" default expression preserves the selected pose");
                for(int i=0;i<hz*4;i++)Frame(1f/hz);
                Check(!auto.State.blinkSuppressed && auto.State.blinkCount>count,c.modelId+" blink resumes after expression fade");
                foreach(string pose in c.Manifest.autonomy.breathing.poseOptions)
                {
                    perf.Select(pose,1);for(int i=0;i<hz*2;i++)Frame(1f/hz);
                    float before=auto.State.chestMotionDegrees;for(int i=0;i<hz*3;i++)Frame(1f/hz);
                    Check(auto.State.poseBreathWeight>.99f && auto.State.chestMotionDegrees-before>.25f,c.modelId+" breath survives static pose "+pose);row.staticPoses++;
                }
                perf.Reset("pose");for(int i=0;i<hz*2;i++)Frame(1f/hz);
                Check(auto.State.poseBreathWeight==0,c.modelId+" static-pose breath releases");
                var sleep=c.Manifest.performance.options.FirstOrDefault(o=>o.id.EndsWith("sleep-loop"));
                if(sleep!=null)
                {
                    perf.Select(sleep.id,1);for(int i=0;i<hz*2;i++)Frame(1f/hz);
                    row.sleepPriority=auto.State.blinkSuppressed && auto.State.blinkWeight==0 && auto.State.poseBreathWeight==0;
                    Check(row.sleepPriority,c.modelId+" sleep retains original face and body");perf.Reset("pose");
                }
                else row.sleepPriority=true;
                for(int i=0;i<hz*2;i++)Frame(1f/hz);
                // Freeze the base animation: isolate actual environment wind from
                // source breathing / dragging. Hair and garment tips still move.
                auto.RestoreMorphs();perf.RestoreMorphs();wind.RestorePose();anim.GetClip("Idle").SampleAnimation(c.gameObject,0);wind.ResetSimulation();
                float hair=wind.HairTravel,cloth=wind.ClothTravel;
                for(int i=0;i<hz*8;i++){wind.RestorePose();wind.Step(1f/hz);}
                row.windWithoutBodyMotion=wind.HairTravel-hair>.01f && wind.ClothTravel-cloth>.001f;
                Check(row.windWithoutBodyMotion,c.modelId+" wind works with frozen body; hair="+(wind.HairTravel-hair)+" cloth="+(wind.ClothTravel-cloth)+" totals="+wind.HairTravel+","+wind.ClothTravel);
                auto.Step(.9f);Check(auto.State.blinkWeight==0,c.modelId+" suspension cannot leave eyes closed");
                auto.Clear();perf.Clear();row.rebindRestored=skin.GetBlendShapeWeight(index)<.001f;
                Check(row.rebindRestored,c.modelId+" leaving restores eyelid baseline");
                auto.Bind(c,perf,745);c.gameObject.SetActive(false);count=auto.State.blinkCount;
                for(int i=0;i<hz*12;i++)auto.Step(1f/hz);
                Check(count==auto.State.blinkCount,c.modelId+" inactive actor has no autonomous work");
            }
            finally{auto.Clear();perf.Clear();UnityEngine.Object.DestroyImmediate(host);UnityEngine.Object.DestroyImmediate(c.gameObject);}
        }
        File.WriteAllText(Path.Combine(Output,"runtime-review.json"),JsonUtility.ToJson(report,true)+"\n");
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");Debug.Log("NATURAL_IDLE_REVIEW_PASS assertions="+report.assertions);
    }
    static void CheckVisibleAmplitude(ViewerCharacter c,Animation anim,Row row)
    {
        var head=CharacterContract.Resolve(c.transform,c.Manifest.rig.head);
        var chest=CharacterContract.Resolve(c.transform,c.Manifest.rig.neck).parent;
        var hips=CharacterContract.Resolve(c.transform,"armature/Hips");
        // The comparison clip stays in the source GLB; production binds only
        // declared clips. Do not add a review-only animation to the mobile app.
        var original=UnityEditor.AssetDatabase.LoadAllAssetsAtPath("Assets/CharacterPackages/Imported/"+c.modelId+"/model.glb")
            .OfType<AnimationClip>().Single(x=>x.name=="Source_Idle");
        var adapted=anim.GetClip("Idle");
        Check(original && adapted,c.modelId+" original idle preserved beside adapted clip");
        original.SampleAnimation(c.gameObject,0);
        Quaternion h0=head.localRotation,c0=chest.localRotation;
        for(int i=0;i<=150;i++)
        {
            float t=original.length*i/150;
            original.SampleAnimation(c.gameObject,t);
            row.sourceHeadRange=Mathf.Max(row.sourceHeadRange,CharacterAutonomy.MotionAngle(h0,head.localRotation));
            row.sourceChestRange=Mathf.Max(row.sourceChestRange,CharacterAutonomy.MotionAngle(c0,chest.localRotation));
            var hp=hips.localPosition;var hq=hips.localRotation;
            adapted.SampleAnimation(c.gameObject,t);
            row.headRange=Mathf.Max(row.headRange,CharacterAutonomy.MotionAngle(h0,head.localRotation));
            row.chestRange=Mathf.Max(row.chestRange,CharacterAutonomy.MotionAngle(c0,chest.localRotation));
            Check(Vector3.Distance(hp,hips.localPosition)<.00001f && CharacterAutonomy.MotionAngle(hq,hips.localRotation)<.003f,
                c.modelId+" amplitude adaptation does not amplify hips/foot motion");
        }
        float gain=c.modelId=="anime-kipfel"?4:3;
        Check(Mathf.Abs(row.headRange/row.sourceHeadRange-gain)<.015f && Mathf.Abs(row.chestRange/row.sourceChestRange-gain)<.015f,
            c.modelId+" actual imported upper-body amplitude gain");
        Check(row.headRange>2.5f && row.chestRange>3.3f && row.chestRange<5,c.modelId+" visible, bounded upper-body idle");
        adapted.SampleAnimation(c.gameObject,0);
    }
    static void Capture(ViewerCharacter c,ViewerController viewer,string suffix)
    {
        var bounds=c.RestBounds();var focus=new Vector3(bounds.center.x,bounds.min.y+bounds.size.y*.73f,bounds.center.z);
        var camera=viewer.viewCamera;camera.aspect=.75f;camera.transform.position=focus+Vector3.forward*bounds.size.y*.86f;camera.transform.LookAt(focus);
        string path=Path.Combine(Output,c.modelId+"-"+suffix+".png");
        // A batch editor has no render-loop skinning update between samples.
        // Render the actual CPU-deformed mesh, avoiding a stale GPU skin cache.
        var baked=new List<GameObject>();var meshes=new List<Mesh>();var skins=c.GetComponentsInChildren<SkinnedMeshRenderer>().Where(s=>s.enabled).ToArray();
        try
        {
            foreach(var skin in skins)
            {
                var mesh=new Mesh();skin.BakeMesh(mesh);meshes.Add(mesh);
                var go=new GameObject("SampledSkin");baked.Add(go);go.transform.SetParent(skin.transform,false);
                go.AddComponent<MeshFilter>().sharedMesh=mesh;go.AddComponent<MeshRenderer>().sharedMaterials=skin.sharedMaterials;skin.enabled=false;
            }
            PortraitRefinementReview.Render(camera,path,720,960);PortraitRefinementReview.Render(camera,path,720,960);
        }
        finally{foreach(var skin in skins)skin.enabled=true;foreach(var go in baked)UnityEngine.Object.DestroyImmediate(go);foreach(var mesh in meshes)UnityEngine.Object.DestroyImmediate(mesh);}
    }
}
