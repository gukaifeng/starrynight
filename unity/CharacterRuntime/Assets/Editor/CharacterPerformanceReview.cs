using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;

// Deterministic data/runtime check on disposable model instances. UI and rendered motion
// checks remain separate: this does not label Edit Mode samples as device performance.
public static class CharacterPerformanceReview
{
    [Serializable] sealed class CaptureCase
    {
        public string id,label;
        public string[] options=Array.Empty<string>(),off=Array.Empty<string>();
        public float seconds=1.2f;
    }
    [Serializable] sealed class CaptureRow
    {
        public string character,variant,label,file;
        public float seconds;
        public string[] selections;
        public Bounds visibleBounds;
        public Vector3 head,cameraPosition;
        public MeshDelta[] meshDeltas;
    }
    [Serializable] sealed class MeshDelta {public string renderer;public bool visible;public int vertices,changedVertices;public float maxDelta,meanDelta;}
    [Serializable] sealed class CaptureReport
    {
        public string status="PASS",scope="actual performance driver and Animation.Sample, actual CPU mesh deltas against default Idle at time zero, temporary baked rendering to avoid same-Editor-frame GPU skinning cache, fixed full-body camera per character; no runtime secondary-motion or device FPS claim";
        public List<CaptureRow> frames=new List<CaptureRow>();
        public string[] unavailable={"Mamehinata source package has no authored prone/sleep or glasses option; crouch and its own bag are shown instead."};
    }
    [Serializable] sealed class RoleReport { public string id;public int options,morphBindings,visibilityBindings,clips,morphTracks,dynamicMorphOptions; }
    [Serializable] sealed class BoneCase {public string character,option;public float rotationFromIdle,positionFromIdle,scaleFromIdle,rotationOverTime,positionOverTime,scaleOverTime;}
    struct BonePose {public Vector3 p,s;public Quaternion q;}
    [Serializable] sealed class Report {public string status="PASS",scope="isolated runtime selections, sampled bone layers and animation phases, morphs, visibility, defaults, lifecycle, character isolation and fixed camera; not a device FPS measurement";public int assertions;public List<RoleReport> characters=new List<RoleReport>();public List<BoneCase> boneCases=new List<BoneCase>();}
    static Report report;
    static void Check(bool value,string message)
    {if(!value)throw new Exception("PERFORMANCE_REVIEW: "+message);report.assertions++;}
    public static void BuildAndReview() {BuildIos.Setup();BuildIos.Validate();Run();Capture();}
    public static void RunAndCapture() {Run();Capture();}
    public static void ReviewAndExportSimulator() {BuildIos.Validate();RunAndCapture();BuildIos.ExportPreparedSimulator();}
    public static void Capture()
    {
        const string scene="Assets/Scenes/ViewerScene.unity";
        string output=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/vrchat-performance/render");
        Directory.CreateDirectory(output);EditorSceneManager.OpenScene(scene);
        var capture=new CaptureReport();var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var host=new GameObject("PerformanceCaptureDriver");var driver=host.AddComponent<CharacterPerformanceDriver>();
        try
        {
            foreach(var character in viewer.characters.Where(c=>CharacterPerformanceContract.IsSupported(c.Manifest.performance) && !c.GetComponent<AvatarControlDriver>()))
            {
                foreach(var actor in viewer.characters)actor.gameObject.SetActive(actor==character);
                character.ApplyContract();CharacterPerformanceBuilder.Validate(character);
                var studio=viewer.GetComponent<CharacterStudioDriver>();studio.Bind(character);
                studio.Configure(new StudioSettings {room=character.modelId=="anime-kipfel"?"garden":"sunroom"},true);
                var player=character.GetComponentInChildren<Animation>(true);player.enabled=true;
                player.Stop();player.GetClip("Idle").SampleAnimation(character.gameObject,0);
                var baseline=character.GetComponentsInChildren<SkinnedMeshRenderer>(true).ToDictionary(s=>s,s=>BakedVertices(s));
                var camera=viewer.viewCamera;var rest=character.RestBounds();
                camera.aspect=.75f;camera.fieldOfView=35;camera.rect=new Rect(0,0,1,1);
                Vector3 focus=new Vector3(rest.center.x,rest.min.y+rest.size.y*.52f,rest.center.z);
                camera.transform.position=focus+new Vector3(rest.size.y*.16f,rest.size.y*.05f,rest.size.y*1.75f);
                camera.transform.LookAt(focus);
                Vector3 fixedCamera=camera.transform.position;Quaternion fixedRotation=camera.transform.rotation;
                var cases=Cases(character.modelId);
                var head=CharacterContract.Resolve(character.transform,character.Manifest.rig.head);
                foreach(var item in cases)
                {
                    driver.Clear();player.Stop();player.GetClip("Idle").SampleAnimation(character.gameObject,0);
                    player.Play("Idle");player["Idle"].time=0;driver.Bind(character);
                    foreach(string id in item.options)
                    {var error=driver.Select(id,1);if(error!=null)throw new Exception("PERFORMANCE_CAPTURE_SELECT: "+character.modelId+"/"+id+"/"+error);}
                    foreach(string id in item.off)
                    {var error=driver.Select(id,0);if(error!=null)throw new Exception("PERFORMANCE_CAPTURE_OFF: "+character.modelId+"/"+id+"/"+error);}
                    float elapsed=0;
                    while(elapsed<item.seconds-.000001f)
                    {
                        float dt=Mathf.Min(1f/60,item.seconds-elapsed);elapsed+=dt;
                        driver.RestoreMorphs();driver.Step(dt);
                        // Edit Mode does not tick the legacy animation clock. Advance its
                        // real states, then let Animation evaluate layers and bone masks.
                        foreach(AnimationState state in player)if(state.enabled)state.time+=dt*state.speed;
                        player.Sample();driver.ApplyFrame();
                        if(!float.IsFinite(head.position.sqrMagnitude))throw new Exception("PERFORMANCE_CAPTURE_NONFINITE: "+item.id);
                    }
                    if(camera.transform.position!=fixedCamera || camera.transform.rotation!=fixedRotation)
                        throw new Exception("PERFORMANCE_CAPTURE_CAMERA_CHANGED: "+item.id);
                    string file=character.modelId+"-"+item.id+".png",path=Path.Combine(output,file);
                    var meshDeltas=MeshDeltas(character,baseline);
                    // Repeated Camera.Render calls in one Editor frame can reuse stale
                    // GPU skinning data. Freeze the actual CPU-evaluated pose just for
                    // this capture; product animation and source meshes stay untouched.
                    CharacterPerformanceVisualProbe.RenderFrozenPose(character,camera,path,1080,1440);
                    capture.frames.Add(new CaptureRow {character=character.modelId,variant=item.id,label=item.label,file=file,seconds=item.seconds,
                        selections=driver.Selections,visibleBounds=VisibleBounds(character),head=head.position,cameraPosition=fixedCamera,meshDeltas=meshDeltas});
                }
                driver.Clear();
            }
            File.WriteAllText(Path.Combine(output,"review.json"),JsonUtility.ToJson(capture,true)+"\n");
            Debug.Log("CHARACTER_PERFORMANCE_CAPTURE_PASS count="+capture.frames.Count);
        }
        finally
        {
            driver.Clear();UnityEngine.Object.DestroyImmediate(host);
            // All capture poses/camera/lighting changes are disposable review state.
            EditorSceneManager.OpenScene(scene);
        }
    }
    static Vector3[] BakedVertices(SkinnedMeshRenderer skin)
    {
        var mesh=new Mesh();try {skin.BakeMesh(mesh,false);return mesh.vertices;}finally {UnityEngine.Object.DestroyImmediate(mesh);}
    }
    static MeshDelta[] MeshDeltas(ViewerCharacter character,Dictionary<SkinnedMeshRenderer,Vector3[]> baseline)
    {
        var results=new List<MeshDelta>();
        foreach(var pair in baseline)
        {
            var skin=pair.Key;var vertices=BakedVertices(skin);float maximum=0;double sum=0;int changed=0;
            for(int i=0;i<vertices.Length;i++)
            {
                float delta=Vector3.Distance(vertices[i],pair.Value[i]);
                if(!float.IsFinite(delta))throw new Exception("PERFORMANCE_CAPTURE_MESH_DELTA_NONFINITE");
                maximum=Mathf.Max(maximum,delta);sum+=delta;if(delta>1e-7f)changed++;
            }
            results.Add(new MeshDelta {renderer=UnityEditor.AnimationUtility.CalculateTransformPath(skin.transform,character.transform),
                visible=skin.enabled && skin.gameObject.activeInHierarchy,vertices=vertices.Length,changedVertices=changed,maxDelta=maximum,meanDelta=(float)(sum/vertices.Length)});
        }
        return results.ToArray();
    }
    static CaptureCase[] Cases(string id)
    {
        if(id=="anime-kipfel")return new[]{
            new CaptureCase {id="default",label="作者默认"},
            new CaptureCase {id="smile",label="猫咪微笑",options=new[]{"kipfel-facial-catsmile"}},
            new CaptureCase {id="dynamic-cry",label="动态哭泣中间帧",options=new[]{"kipfel-facial-cry"},seconds=3.7f},
            new CaptureCase {id="sit",label="作者坐姿",options=new[]{"kipfel-sit"}},
            new CaptureCase {id="crouch",label="作者蹲姿",options=new[]{"kipfel-crouch-still"}},
            new CaptureCase {id="prone",label="作者俯卧",options=new[]{"kipfel-prone01-still"}},
            new CaptureCase {id="sleep",label="躺下并衔接睡眠循环",options=new[]{"kipfel-afk-stand-to-sleep","kipfel-facial-sleep"},seconds=9.2f},
            new CaptureCase {id="peace",label="作者剪刀手",options=new[]{"kipfel-hand-peace"}},
            new CaptureCase {id="ears-tail",label="展开耳朵和卷尾",options=new[]{"kipfel-catear-up","kipfel-cattail-roll"}},
            new CaptureCase {id="glasses",label="作者眼镜",options=new[]{"outfit-glasses"}},
            new CaptureCase {id="bag-off",label="作者摘包动作之后",off=new[]{"outfit-bag"},seconds=2f}
        };
        if(id=="anime-mamehinata")return new[]{
            new CaptureCase {id="default",label="作者默认"},
            new CaptureCase {id="smile",label="灿烂笑容",options=new[]{"f-bigsmile"}},
            new CaptureCase {id="dynamic-exciting",label="动态兴奋表情中间帧",options=new[]{"f-exciting"},seconds=1.2f},
            new CaptureCase {id="sit",label="作者坐姿",options=new[]{"mamehinata-sit"}},
            new CaptureCase {id="crouch",label="作者蹲姿",options=new[]{"mamehinata-crouch-still"}},
            new CaptureCase {id="peace",label="作者剪刀手",options=new[]{"mamehinata-peace"}},
            new CaptureCase {id="ears-tail",label="耳朵轻动与摇尾",options=new[]{"dogear-pyoko","dogtail-upwag"},seconds=2.1f},
            new CaptureCase {id="bag-off",label="作者斜挎包开关",off=new[]{"outfit-bodybag"}}
        };
        throw new Exception("PERFORMANCE_CAPTURE_CASES_REQUIRED: "+id);
    }
    static Bounds VisibleBounds(ViewerCharacter character)
    {
        var baked=new Mesh();var bounds=new Bounds();bool first=true;
        try
        {
            foreach(var renderer in character.GetComponentsInChildren<Renderer>(true))
            {
                if(!renderer.enabled || !renderer.gameObject.activeInHierarchy)continue;
                Bounds local;
                if(renderer is SkinnedMeshRenderer skin) {skin.BakeMesh(baked,true);baked.RecalculateBounds();local=baked.bounds;}
                else if(renderer.GetComponent<MeshFilter>() is MeshFilter filter && filter.sharedMesh)local=filter.sharedMesh.bounds;
                else continue;
                for(int i=0;i<8;i++)
                {
                    Vector3 p=renderer.transform.TransformPoint(local.center+Vector3.Scale(local.extents,new Vector3((i&1)==0?-1:1,(i&2)==0?-1:1,(i&4)==0?-1:1)));
                    if(!float.IsFinite(p.sqrMagnitude))throw new Exception("PERFORMANCE_CAPTURE_MESH_NONFINITE");
                    if(first){bounds=new Bounds(p,Vector3.zero);first=false;}else bounds.Encapsulate(p);
                }
            }
        }
        finally {UnityEngine.Object.DestroyImmediate(baked);}
        if(first)throw new Exception("PERFORMANCE_CAPTURE_NO_VISIBLE_MESH");return bounds;
    }
    public static void Run()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        report=new Report();var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        Vector3 cameraPosition=viewer.viewCamera.transform.position;Quaternion cameraRotation=viewer.viewCamera.transform.rotation;
        // This review samples legacy Animation layers and explicit morph/visibility
        // bindings. Mecanim controls have parameter-based selections (including
        // valid zero-valued choices), and are reviewed by PortableAvatarReview.
        var roles=viewer.characters.Where(c=>CharacterPerformanceContract.IsSupported(c.Manifest.performance) && !c.GetComponent<AvatarControlDriver>()).ToArray();Check(roles.Length>0,"no legacy performance characters");
        var host=new GameObject("PerformanceReviewDriver");
        var driver=host.AddComponent<CharacterPerformanceDriver>();
        try
        {
            foreach(var source in roles)
            {
                GameObject instance=UnityEngine.Object.Instantiate(source.gameObject);instance.SetActive(true);
                try
                {
                    var character=instance.GetComponent<ViewerCharacter>();character.ApplyContract();
                    CharacterPerformanceBuilder.Validate(character);
                    var player=character.GetComponentInChildren<Animation>(true);
                    float ClipLength(string name) => string.IsNullOrEmpty(name)?0:player.GetClip(name)?.length ?? 0;
                    player.enabled=true;player.Play("Idle");player["Idle"].time=0;player.Sample();
                    var rootPosition=character.transform.position;var rootRotation=character.transform.rotation;var rootScale=character.transform.localScale;
                    var profile=character.Manifest.performance;
                    var initialMorphs=new Dictionary<(SkinnedMeshRenderer,int),float>();
                    var initialVisibility=new Dictionary<Renderer,bool>();
                    int dynamicMorphOptions=0;
                    foreach(var option in profile.options)
                    {
                        foreach(var binding in option.morphs.Concat(option.offMorphs).Concat(option.morphTracks.Select(t=>new ShapeBinding {renderer=t.renderer,shape=t.shape})))
                        {
                            var skin=CharacterContract.Resolve(character.transform,binding.renderer).GetComponent<SkinnedMeshRenderer>();
                            int index=skin.sharedMesh.GetBlendShapeIndex(binding.shape);initialMorphs[(skin,index)]=skin.GetBlendShapeWeight(index);
                        }
                        foreach(var binding in option.visibility.Concat(option.offVisibility))
                        {var renderer=CharacterContract.Resolve(character.transform,binding.path).GetComponent<Renderer>();initialVisibility[renderer]=renderer.enabled;}
                    }
                    driver.Bind(character);
                    void Frame(int count=40)
                    {
                        for(int i=0;i<count;i++)
                        {driver.RestoreMorphs();driver.Step(.05f);foreach(AnimationState state in player)if(state.enabled)state.time+=.05f*state.speed;player.Sample();driver.ApplyFrame();}
                    }
                    foreach(var option in profile.options)
                    {
                        Check(driver.Reset()==null,character.modelId+" reset");Frame();
                        Check(driver.Select(option.id,1)==null,character.modelId+" select "+option.id);Frame();
                        if(!string.IsNullOrEmpty(option.clip) && option.kind!="toggle" && driver.Selections.Contains(option.id))
                            CheckBones(character,option,player,driver);
                        if(option.kind!="motion" || option.loop)
                        {
                            Check(driver.Selections.Contains(option.id),character.modelId+" holds "+option.id);
                            foreach(var binding in option.morphs.Where(b=>!option.morphTracks.Any(t=>t.renderer==b.renderer && t.shape==b.shape)))
                            {
                                var skin=CharacterContract.Resolve(character.transform,binding.renderer).GetComponent<SkinnedMeshRenderer>();
                                int index=skin.sharedMesh.GetBlendShapeIndex(binding.shape);float target=binding.weight*CharacterContract.MorphScale(skin,index);
                                Check(Mathf.Abs(skin.GetBlendShapeWeight(index)-target)<.002f,character.modelId+" morph "+option.id+"/"+binding.shape);
                            }
                            foreach(var binding in option.visibility)
                                Check(CharacterContract.Resolve(character.transform,binding.path).GetComponent<Renderer>().enabled==binding.visible,character.modelId+" visibility "+option.id+"/"+binding.path);
                        }
                        if(option.kind=="toggle")
                        {
                            Check(driver.Select(option.id,0)==null,character.modelId+" toggle off "+option.id);Frame();
                            Check(!driver.Selections.Contains(option.id),character.modelId+" toggle removed "+option.id);
                            foreach(var binding in option.offMorphs)
                            {
                                var skin=CharacterContract.Resolve(character.transform,binding.renderer).GetComponent<SkinnedMeshRenderer>();
                                int index=skin.sharedMesh.GetBlendShapeIndex(binding.shape);
                                Check(Mathf.Abs(skin.GetBlendShapeWeight(index)-binding.weight*CharacterContract.MorphScale(skin,index))<.002f,character.modelId+" off morph "+option.id);
                            }
                            foreach(var binding in option.offVisibility)
                                Check(CharacterContract.Resolve(character.transform,binding.path).GetComponent<Renderer>().enabled==binding.visible,character.modelId+" off visibility "+option.id);
                        }
                        if(option.kind=="motion" && !option.loop)
                        {
                            float duration=option.duration>0?option.duration:Mathf.Max(ClipLength(option.clip),
                                option.morphTracks.Select(t=>t.keys[t.keys.Length-1].time).DefaultIfEmpty(0).Max());
                            Frame(Mathf.CeilToInt((duration+2)/.05f));Check(!driver.Selections.Contains(option.id),character.modelId+" motion expires "+option.id);
                            if(!string.IsNullOrEmpty(option.next))Check(driver.Selections.Contains(option.next),character.modelId+" authored successor "+option.id);
                        }
                        if(option.morphTracks.Length>0)
                        {
                            // Choose a genuinely changing track and two nonterminal authored
                            // keys. Compare actual mesh output with its expected eased overlay,
                            // so replacing the animation with its last value cannot pass.
                            float duration=option.duration>0?option.duration:Mathf.Max(ClipLength(option.clip),
                                option.morphTracks.Max(t=>t.keys[t.keys.Length-1].time));
                            var changing=option.morphTracks.Select(t=>new {track=t,keys=t.keys.Where(k=>k.time>.001f && k.time<duration-.001f).ToArray()})
                                .Where(v=>v.keys.Length>1 && v.keys.Max(k=>k.value)-v.keys.Min(k=>k.value)>.01f)
                                .OrderByDescending(v=>v.keys.Max(k=>k.value)-v.keys.Min(k=>k.value)).FirstOrDefault();
                            if(changing!=null)
                            {
                                dynamicMorphOptions++;
                                var track=changing.track;var skin=CharacterContract.Resolve(character.transform,track.renderer).GetComponent<SkinnedMeshRenderer>();
                                int index=skin.sharedMesh.GetBlendShapeIndex(track.shape);float scale=CharacterContract.MorphScale(skin,index);
                                var ordered=changing.keys.OrderBy(k=>k.value).ToArray();
                                foreach(var key in new[]{ordered[0],ordered[ordered.Length-1]})
                                {
                                    driver.Reset();Frame();driver.Select(option.id,1);
                                    float elapsed=0,weight=0,basis=0;
                                    while(elapsed<key.time-.000001f)
                                    {
                                        float dt=Mathf.Min(.05f,key.time-elapsed);elapsed+=dt;
                                        weight=Mathf.Lerp(weight,1,1-Mathf.Exp(-9*dt));if(1-weight<.0005f)weight=1;
                                        driver.RestoreMorphs();driver.Step(dt);foreach(AnimationState state in player)if(state.enabled)state.time+=dt*state.speed;
                                        player.Sample();basis=skin.GetBlendShapeWeight(index);driver.ApplyFrame();
                                    }
                                    var authoredOff=Array.Find(option.offMorphs,b=>b.renderer==track.renderer && b.shape==track.shape);
                                    var authoredStatic=Array.Find(option.morphs,b=>b.renderer==track.renderer && b.shape==track.shape);
                                    float expected=basis;
                                    if(authoredStatic!=null || authoredOff!=null)
                                        expected=Mathf.Lerp(authoredOff!=null?authoredOff.weight*scale:basis,authoredStatic!=null?authoredStatic.weight*scale:basis,weight);
                                    expected=Mathf.Lerp(expected,key.value*scale,weight);
                                    Check(Mathf.Abs(skin.GetBlendShapeWeight(index)-expected)<.003f,character.modelId+" dynamic morph "+option.id+"/"+track.shape+" t="+key.time);
                                    Check(Mathf.Abs(CharacterPerformanceDriver.Evaluate(track,key.time)-key.value)<.00001f,character.modelId+" exact authored key "+option.id);
                                }
                            }
                        }
                        Check(character.transform.position==rootPosition && character.transform.rotation==rootRotation && character.transform.localScale==rootScale,character.modelId+" fixed root "+option.id);
                    }
                    foreach(var group in profile.groups)
                    {
                        var options=profile.options.Where(o=>o.group==group.id && o.kind!="toggle").Take(2).ToArray();
                        if(options.Length<2)continue;
                        driver.Select(options[0].id,1);driver.Select(options[1].id,1);
                        Check(!driver.Selections.Contains(options[0].id) && driver.Selections.Contains(options[1].id),character.modelId+" group exclusive "+group.id);
                    }
                    Check(driver.Select("missing-option",1)=="PERFORMANCE_OPTION_UNKNOWN",character.modelId+" unknown option");
                    Check(driver.Reset("missing-group")=="PERFORMANCE_GROUP_UNKNOWN",character.modelId+" unknown group");
                    driver.Reset();Frame();
                    Check(driver.Selections.OrderBy(s=>s).SequenceEqual(profile.options.Where(o=>o.defaultOn).Select(o=>o.id).OrderBy(s=>s)),character.modelId+" default selections");
                    driver.Clear();
                    foreach(var pair in initialMorphs)Check(Mathf.Abs(pair.Key.Item1.GetBlendShapeWeight(pair.Key.Item2)-pair.Value)<.0001f,character.modelId+" restores original nonzero morph");
                    foreach(var pair in initialVisibility)Check(pair.Key.enabled==pair.Value,character.modelId+" restores default visibility");
                    var withoutPerformance=viewer.characters.FirstOrDefault(c=>!CharacterPerformanceContract.IsSupported(c.Manifest.performance));
                    if(withoutPerformance)driver.Bind(withoutPerformance);else driver.Clear();
                    Check(driver.Selections.Length==0 && !driver.Supported && driver.Select(profile.options[0].id,1)=="PERFORMANCE_UNSUPPORTED",character.modelId+" character isolation");
                    driver.Clear();
                    report.characters.Add(new RoleReport {id=character.modelId,options=profile.options.Length,clips=profile.Clips.Count(),morphBindings=initialMorphs.Count,visibilityBindings=initialVisibility.Count,
                        morphTracks=profile.options.Sum(o=>o.morphTracks.Length),dynamicMorphOptions=dynamicMorphOptions});
                }
                finally {driver.Clear();UnityEngine.Object.DestroyImmediate(instance);}
            }
            Check(viewer.viewCamera.transform.position==cameraPosition && viewer.viewCamera.transform.rotation==cameraRotation,"camera unchanged for every option");
        }
        finally {UnityEngine.Object.DestroyImmediate(host);}
        string path=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/vrchat-performances/runtime-review.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,JsonUtility.ToJson(report,true)+"\n");
        Debug.Log("CHARACTER_PERFORMANCE_REVIEW_PASS assertions="+report.assertions);
    }
    static void CheckBones(ViewerCharacter character,CharacterPerformanceOption option,Animation player,CharacterPerformanceDriver driver)
    {
        var state=player["__performance_"+option.id];
        Check(state!=null && state.enabled && state.weight>.99f,character.modelId+" real animation layer enabled "+option.id);
        var bones=option.bones.Select(p=>CharacterContract.Resolve(character.transform,p)).ToArray();
        BonePose[] Pose()=>bones.Select(b=>new BonePose {p=b.localPosition,q=b.localRotation,s=b.localScale}).ToArray();
        float time=state.time;bool active=state.enabled;
        void Sample(float t) {driver.RestoreMorphs();state.time=t;player.Sample();driver.ApplyFrame();}
        var item=new BoneCase {character=character.modelId,option=option.id};
        try
        {
            driver.RestoreMorphs();state.enabled=false;player.Sample();var idle=Pose();
            state.enabled=true;Sample(0);var first=Pose();
            foreach(float phase in new[]{.17f,.43f,.71f})
            {
                Sample(state.length*phase);var current=Pose();
                for(int i=0;i<bones.Length;i++)
                {
                    Check(float.IsFinite(current[i].p.sqrMagnitude) && float.IsFinite(current[i].q.x+current[i].q.y+current[i].q.z+current[i].q.w),character.modelId+" finite performance bone "+option.id);
                    item.rotationFromIdle=Mathf.Max(item.rotationFromIdle,Quaternion.Angle(current[i].q,idle[i].q));
                    item.positionFromIdle=Mathf.Max(item.positionFromIdle,Vector3.Distance(current[i].p,idle[i].p));
                    item.scaleFromIdle=Mathf.Max(item.scaleFromIdle,Vector3.Distance(current[i].s,idle[i].s));
                    item.rotationOverTime=Mathf.Max(item.rotationOverTime,Quaternion.Angle(current[i].q,first[i].q));
                    item.positionOverTime=Mathf.Max(item.positionOverTime,Vector3.Distance(current[i].p,first[i].p));
                    item.scaleOverTime=Mathf.Max(item.scaleOverTime,Vector3.Distance(current[i].s,first[i].s));
                }
            }
            if(option.id.EndsWith("-sit",StringComparison.Ordinal) || option.id.Contains("crouch") || option.id.Contains("prone") ||
                option.id.Contains("afk-stand-to-sleep") || option.id.EndsWith("-peace",StringComparison.Ordinal) || option.id.EndsWith("-breath",StringComparison.Ordinal))
                Check(item.rotationFromIdle>.01f || item.positionFromIdle>.00001f || item.scaleFromIdle>.00001f,character.modelId+" authored pose actually affects bones "+option.id);
            if(option.id.Contains("afk-stand-to-sleep") || option.id.EndsWith("-breath",StringComparison.Ordinal))
                Check(item.rotationOverTime>.01f || item.positionOverTime>.00001f || item.scaleOverTime>.00001f,character.modelId+" authored animation changes over time "+option.id);
            report.boneCases.Add(item);
        }
        finally {state.enabled=active;Sample(time);}
    }
}
