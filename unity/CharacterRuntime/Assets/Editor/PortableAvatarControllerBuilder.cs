using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine;
using ModelSpace;

// Typed data -> native Mecanim assets. Unity evaluates state transitions, blend
// trees, masks and curve interpolation; the app does not invent another Animator.
public static class PortableAvatarControllerBuilder
{
    [Serializable] class Data {public int schemaVersion;public AvatarParameter[] parameters;public AvatarControl[] controls;public Graph[] controllers;public Mask[] masks;public string[] baselineFallbackMotions;}
    [Serializable] class Graph {public string id;public int playable;public Layer[] layers;public Machine[] machines;public State[] states;public Transition[] transitions;public Blend[] blends;}
    [Serializable] class Layer {public string name,root,mask;public float weight;public bool additive;public int synced;}
    [Serializable] class Machine {public string id,name,@default;public string[] states,children,any,entry;public AvatarBehavior[] behaviors;public MachineLink[] machineTransitions;}
    [Serializable] class MachineLink {public string machine;public string[] transitions;}
    [Serializable] class State {public string id,name,motion,timeParameter,speedParameter;public float speed,cycle;public bool writeDefaults,mirror;public string[] transitions;public AvatarBehavior[] behaviors;}
    [Serializable] class Condition {public string parameter;public int mode;public float threshold;}
    [Serializable] class Transition {public string id,target,machine;public bool exit,muted,solo,hasExitTime,fixedDuration,ordered,self;public float duration,offset,exitTime;public int interrupt;public Condition[] conditions;}
    [Serializable] class Blend {public string id,name,x,y;public int kind;public bool automatic;public float minimum,maximum;public Child[] children;}
    [Serializable] class Child {public string motion,parameter;public float threshold,x,y,speed,cycle;public bool mirror;}
    [Serializable] class Mask {public string id,body;public MaskPath[] transforms;}
    [Serializable] class MaskPath {public string path;public bool active;}
    [Serializable] class Geometry {public Human[] human;public Node[] nodes;public Skin[] skins;}
    [Serializable] class Human {public string human,path;}
    [Serializable] class Node {public string path;public bool active;}
    [Serializable] class Skin {public string path;public bool enabled;}
    [Serializable] class MotionList {public MotionSpec[] motions;}
    [Serializable] class MotionSpec {public string guid,name;public bool loop,humanoid;public float duration;public float[] times;public Track[] tracks;public Curve[] curves;public ObjectCurve[] objects;}
    [Serializable] class Track {public string path;public float[] times;public Vector3[] positions,scales;public Quaternion[] rotations;}
    [Serializable] class Key {public float time,value,inTangent,outTangent,inWeight,outWeight;public int weightedMode;public bool steppedIn,steppedOut;}
    [Serializable] class Curve {public string path,component,property;public Key[] keys;}
    [Serializable] class ObjectCurve {public string path,component,property;public ObjectKey[] keys;}
    [Serializable] class ObjectKey {public float time;public string guid,path;}
    static readonly Dictionary<string,Type> Components=new Dictionary<string,Type> {
        {"UnityEngine.SkinnedMeshRenderer",typeof(SkinnedMeshRenderer)}, {"UnityEngine.MeshRenderer",typeof(MeshRenderer)},
        {"UnityEngine.GameObject",typeof(GameObject)}, {"UnityEngine.Light",typeof(Light)}, {"UnityEngine.AudioSource",typeof(AudioSource)}, {"UnityEngine.Animator",typeof(Animator)}
    };
    public static void Prepare(GameObject character,string folder,AnimationClip idle)
    {
        string path=folder+"/avatar-controls.json";if(!File.Exists(path))return;
        var data=JsonUtility.FromJson<Data>(File.ReadAllText(path));
        if((data.schemaVersion!=1 && data.schemaVersion!=2) || data.controllers.Length>8 || data.controls.Length>2048)throw new Exception("AVATAR_CONTROL_SCHEMA_INVALID");
        var root=character.transform.Find("Avatar");if(!root)throw new Exception("AVATAR_CONTROL_ROOT_MISSING");
        var manifest=JsonUtility.FromJson<CharacterManifest>(File.ReadAllText(folder+"/character.json"));
        var automaticControls=new HashSet<string>((manifest.performance?.options ?? Array.Empty<CharacterPerformanceOption>())
            .Where(o=>o.ai?.automatic==true && !string.IsNullOrEmpty(o.control?.id)).Select(o=>o.control.id));
        var conversationalParameters=new HashSet<string>(data.controls.Where(c=>automaticControls.Contains(c.id)).Select(c=>c.parameter));
        var geometry=JsonUtility.FromJson<Geometry>(File.ReadAllText(folder+"/avatar-geometry.json"));
        var humanPaths=new HashSet<string>(geometry.human.Select(h=>h.path));
        foreach(var n in geometry.nodes) {var t=string.IsNullOrEmpty(n.path)?root:root.Find(n.path);if(t)t.gameObject.SetActive(n.active);}
        foreach(var s in geometry.skins) {var t=root.Find(s.path);if(t && t.TryGetComponent<Renderer>(out var renderer))renderer.enabled=s.enabled;}
        string output=folder+"/BakedControllers";Directory.CreateDirectory(output);
        string assetPath=output+"/Avatar.controller";
        // Only this generated controller asset is replaced; source IR is immutable.
        if(File.Exists(assetPath))AssetDatabase.DeleteAsset(assetPath);
        var controller=AnimatorController.CreateAnimatorControllerAtPath(assetPath);
        controller.layers=Array.Empty<AnimatorControllerLayer>();
        T Own<T>(T value) where T:UnityEngine.Object {AssetDatabase.AddObjectToAsset(value,controller);return value;}
        foreach(var p in data.parameters)
        {
            if(string.IsNullOrEmpty(p.name) || p.name.Length>256 || !float.IsFinite(p.initial))throw new Exception("AVATAR_PARAMETER_INVALID");
            var type=p.kind=="bool"?AnimatorControllerParameterType.Bool:p.kind=="int"?AnimatorControllerParameterType.Int:p.kind=="trigger"?AnimatorControllerParameterType.Trigger:AnimatorControllerParameterType.Float;
            controller.AddParameter(new AnimatorControllerParameter {name=p.name,type=type,defaultFloat=p.initial,defaultInt=Mathf.RoundToInt(p.initial),defaultBool=p.initial>.5f});
        }
        var baseline=Own(new AnimationClip {name="Host baseline",legacy=false,wrapMode=WrapMode.Loop});
        foreach(var binding in AnimationUtility.GetCurveBindings(idle))
        {
            if(!binding.path.StartsWith("Avatar/",StringComparison.Ordinal))continue;
            var target=binding;target.path=target.path.Substring(7);AnimationUtility.SetEditorCurve(baseline,target,AnimationUtility.GetEditorCurve(idle,binding));
        }
        // An unbound morph otherwise retains the last blended frame when a
        // write-defaults state relinquishes it. Anchor to the imported neutral
        // weights in the bottom layer, below every authored expression.
        foreach(var skin in root.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            for(int index=0;index<skin.sharedMesh.blendShapeCount;index++)
                AnimationUtility.SetEditorCurve(baseline,EditorCurveBinding.FloatCurve(
                    AnimationUtility.CalculateTransformPath(skin.transform,root),typeof(SkinnedMeshRenderer),
                    "blendShape."+skin.sharedMesh.GetBlendShapeName(index)),
                    AnimationCurve.Constant(0,1,skin.GetBlendShapeWeight(index)));
        var neutralFX=Own(new AnimationClip {name="Host neutral FX passthrough",legacy=false});
        var baseMachine=Own(new AnimatorStateMachine {name="Host baseline"});var baseState=baseMachine.AddState("Idle");baseState.motion=baseline;baseMachine.defaultState=baseState;
        controller.AddLayer(new AnimatorControllerLayer {name="Host baseline",defaultWeight=1,stateMachine=baseMachine});
        var motions=JsonUtility.FromJson<MotionList>(CharacterMotionData.Read(folder+"/avatar-motions.json"));
        var clips=new Dictionary<string,AnimationClip>();
        foreach(var source in motions.motions)
        {
            var clip=Own(new AnimationClip {name=source.name,legacy=false,frameRate=60,wrapMode=source.loop?WrapMode.Loop:WrapMode.ClampForever});
            foreach(var track in source.tracks)
            {
                if(!string.IsNullOrEmpty(track.path) && !root.Find(track.path))continue;
                void Axis(string prop,int axis,int dimensions)
                {
                    var sampleTimes=track.times?.Length>0?track.times:source.times;
                    var keys=new Keyframe[sampleTimes.Length];
                    for(int i=0;i<keys.Length;i++)
                    {
                        float value=prop=="m_LocalPosition"?track.positions[i][axis]:prop=="m_LocalScale"?track.scales[i][axis]:track.rotations[i][axis];
                        keys[i]=new Keyframe(sampleTimes[i],value);
                    }
                    var curve=new AnimationCurve(keys);
                    for(int i=0;i<keys.Length;i++) {AnimationUtility.SetKeyLeftTangentMode(curve,i,AnimationUtility.TangentMode.Linear);AnimationUtility.SetKeyRightTangentMode(curve,i,AnimationUtility.TangentMode.Linear);}
                    AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(track.path,typeof(Transform),prop+"."+"xyzw"[axis]),curve);
                }
                for(int axis=0;axis<3;axis++) {Axis("m_LocalPosition",axis,3);Axis("m_LocalScale",axis,3);}
                for(int axis=0;axis<4;axis++)Axis("m_LocalRotation",axis,4);
            }
            foreach(var curve in source.curves)
            {
                if(!Components.TryGetValue(curve.component,out var type))continue;
                var target=string.IsNullOrEmpty(curve.path)?root:root.Find(curve.path);if(!target)continue;
                if(type!=typeof(GameObject) && !target.GetComponent(type) && type!=typeof(Animator))continue;
                if(type==typeof(Animator) && !data.parameters.Any(p=>p.name==curve.property))continue;
                if(type==typeof(SkinnedMeshRenderer) && curve.property.StartsWith("blendShape.") && target.GetComponent<SkinnedMeshRenderer>().sharedMesh.GetBlendShapeIndex(curve.property.Substring(11))<0)continue;
                float scale=1;
                if(type==typeof(SkinnedMeshRenderer) && curve.property.StartsWith("blendShape."))
                {var skin=target.GetComponent<SkinnedMeshRenderer>();scale=CharacterContract.MorphScale(skin,skin.sharedMesh.GetBlendShapeIndex(curve.property.Substring(11)))/100f;}
                var values=curve.keys.Select(k=>new Keyframe(k.time,k.value*scale,k.steppedIn?float.PositiveInfinity:k.inTangent*scale,k.steppedOut?float.PositiveInfinity:k.outTangent*scale,k.inWeight,k.outWeight) {weightedMode=(WeightedMode)k.weightedMode}).ToArray();
                AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(curve.path,type,curve.property),new AnimationCurve(values));
            }
            foreach(var curve in source.objects)
            {
                if(!Components.TryGetValue(curve.component,out var type) || !curve.property.StartsWith("m_Materials.Array.data[",StringComparison.Ordinal))continue;
                var target=root.Find(curve.path);if(!target || !target.GetComponent(type))continue;
                var keys=curve.keys.Select(k=>new ObjectReferenceKeyframe {time=k.time,value=AssetDatabase.LoadAssetAtPath<Material>(folder+"/BakedMaterials/mat_"+k.guid+".mat")}).ToArray();
                if(keys.Any(k=>!k.value))throw new Exception("AVATAR_ANIMATED_MATERIAL_MISSING: "+source.name);
                AnimationUtility.SetObjectReferenceCurve(clip,EditorCurveBinding.PPtrCurve(curve.path,type,curve.property),keys);
            }
            var clipSettings=AnimationUtility.GetAnimationClipSettings(clip);clipSettings.loopTime=source.loop;AnimationUtility.SetAnimationClipSettings(clip,clipSettings);clip.EnsureQuaternionContinuity();
            clips.Add(source.guid,clip);
        }
        // Humanoid source samples are absolute Generic transform curves. Unity's
        // additive humanoid reference metadata does not subtract that rest pose
        // from these Generic curves. Bake explicit deltas ONLY for additive use;
        // override clips and the original preview library stay absolute.
        var additiveClips=new Dictionary<string,AnimationClip>();
        AnimationClip AdditiveClip(string id,string graphID,HashSet<string> paths) {
            string key=graphID+"/"+id;
            if(additiveClips.TryGetValue(key,out var cached))return cached;
            var source=motions.motions.FirstOrDefault(m=>m.guid==id);
            var original=source!=null?clips[id]:neutralFX;
            if(paths.Count==0)return original;
            var clip=Own(UnityEngine.Object.Instantiate(original));clip.name=(source?.name??"Host neutral")+" / additive delta";
            // Empty/partial additive states otherwise write the Generic rig's
            // bind rotation as their default, folding the body between breaths.
            // Anchor every channel owned by this additive graph to zero motion.
            foreach(string path in paths) {
                for(int axis=0;axis<4;axis++)AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(path,typeof(Transform),"m_LocalRotation."+"xyzw"[axis]),AnimationCurve.Constant(0,Mathf.Max(.01f,source?.duration??1),axis==3?1:0));
                for(int axis=0;axis<3;axis++) {
                    AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(path,typeof(Transform),"m_LocalPosition."+"xyz"[axis]),AnimationCurve.Constant(0,Mathf.Max(.01f,source?.duration??1),0));
                    AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(path,typeof(Transform),"m_LocalScale."+"xyz"[axis]),AnimationCurve.Constant(0,Mathf.Max(.01f,source?.duration??1),1));
                }
            }
            foreach(var track in source?.tracks??Array.Empty<Track>()) {
                if(!string.IsNullOrEmpty(track.path) && !root.Find(track.path))continue;
                var times=track.times?.Length>0?track.times:source.times;
                for(int axis=0;axis<4;axis++) {
                    var values=track.rotations.Select(q=>(Quaternion.Inverse(track.rotations[0])*q).normalized[axis]).ToArray();
                    AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(track.path,typeof(Transform),"m_LocalRotation."+"xyzw"[axis]),Linear(times,values));
                }
                for(int axis=0;axis<3;axis++) {
                    AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(track.path,typeof(Transform),"m_LocalPosition."+"xyz"[axis]),Linear(times,track.positions.Select(p=>p[axis]-track.positions[0][axis]).ToArray()));
                    float baselineScale=track.scales[0][axis];
                    if(Mathf.Abs(baselineScale)<.000001f)throw new Exception("AVATAR_ADDITIVE_ZERO_SCALE: "+source.name+"/"+track.path);
                    AnimationUtility.SetEditorCurve(clip,EditorCurveBinding.FloatCurve(track.path,typeof(Transform),"m_LocalScale."+"xyz"[axis]),Linear(times,track.scales.Select(s=>s[axis]/baselineScale).ToArray()));
                }
            }
            clip.EnsureQuaternionContinuity();additiveClips[key]=clip;return clip;
        }
        var masks=new Dictionary<string,AvatarMask>();
        foreach(var source in data.masks)
        {
            var mask=Own(new AvatarMask {name="Mask "+source.id});mask.transformCount=geometry.nodes.Length;
            for(int i=0;i<geometry.nodes.Length;i++)
            {
                string node=geometry.nodes[i].path;bool active=true;
                var authored=source.transforms.Where(t=>node==t.path || node.StartsWith(t.path+"/",StringComparison.Ordinal)).OrderByDescending(t=>t.path.Length).FirstOrDefault();
                if(authored!=null)active=authored.active;
                // Humanoid muscle masks apply to mapped human bones. Accessory
                // children (ears, tail, sleeves) have their own Transform masks.
                var human=geometry.human.FirstOrDefault(h=>node==h.path);
                if(human!=null && source.body?.Length>=13*8)
                {
                    string n=human.human;int part=n.Contains("Finger") || n.Contains("Thumb") || n.Contains("Index") || n.Contains("Middle") || n.Contains("Ring") || n.Contains("Little")?(n.StartsWith("Left")?7:8):n.Contains("Arm") || n.Contains("Shoulder") || n.Contains("Hand")?(n.StartsWith("Left")?5:6):n.Contains("Leg") || n.Contains("Foot") || n.Contains("Toes")?(n.StartsWith("Left")?3:4):n.Contains("Head") || n.Contains("Neck") || n.Contains("Eye") || n.Contains("Jaw")?2:1;
                    active=active && source.body.Substring(part*8,8)!="00000000";
                }
                mask.SetTransformPath(i,node);mask.SetTransformActive(i,active);
            }
            masks.Add(source.id,mask);
        }
        var groups=new List<AvatarLayerGroup>();
        foreach(var graph in data.controllers)
        {
            var graphClips=new Dictionary<string,AnimationClip>();
            masks.TryGetValue(graph.layers.FirstOrDefault()?.mask??"",out var firstFXMask);
            AnimationClip GraphClip(string id) {
                if(graph.playable!=5)return clips[id];
                if(graphClips.TryGetValue(id,out var cached))return cached;
                var source=motions.motions.First(m=>m.guid==id);
                if(!source.humanoid)return clips[id];
                // The default FX mask excludes muscles; a custom first-layer
                // mask may explicitly allow some. Preserve that distinction
                // after muscle samples become ordinary Generic transforms.
                var projected=Own(UnityEngine.Object.Instantiate(clips[id]));projected.name=source.name+" / FX projection";
                foreach(var binding in AnimationUtility.GetCurveBindings(projected)) {
                    int node=Array.FindIndex(geometry.nodes,n=>n.path==binding.path);
                    bool humanAllowed=firstFXMask && node>=0 && firstFXMask.GetTransformActive(node);
                    if(binding.type==typeof(Transform) && (binding.path=="" || (humanPaths.Contains(binding.path) && !humanAllowed)))AnimationUtility.SetEditorCurve(projected,binding,null);
                }
                graphClips[id]=projected;return projected;
            }
            var graphMachines=graph.machines.ToDictionary(m=>m.id);
            IEnumerable<string> DescendantStates(string id) => graphMachines[id].states.Concat(graphMachines[id].children.SelectMany(DescendantStates));
            var additiveStates=new HashSet<string>(graph.layers.Where(l=>l.additive).SelectMany(l=>DescendantStates(l.root)));
            var blendSpecs=graph.blends.ToDictionary(b=>b.id);
            IEnumerable<string> Leaves(string id) => blendSpecs.TryGetValue(id,out var blend)?blend.children.SelectMany(c=>Leaves(c.motion)):new[]{id};
            var additiveIDs=new HashSet<string>(graph.states.Where(s=>additiveStates.Contains(s.id)).SelectMany(s=>Leaves(s.motion)));
            var additivePaths=new HashSet<string>(motions.motions.Where(m=>additiveIDs.Contains(m.guid)).SelectMany(m=>m.tracks.Select(t=>t.path)).Where(p=>string.IsNullOrEmpty(p) || root.Find(p)));
            if(additiveIDs.Overlaps(data.baselineFallbackMotions??Array.Empty<string>()))
                additivePaths.UnionWith(AnimationUtility.GetCurveBindings(baseline).Where(b=>b.type==typeof(Transform)).Select(b=>b.path));
            var machines=graph.machines.ToDictionary(m=>m.id,m=>Own(new AnimatorStateMachine {name=m.name}));
            var states=graph.states.ToDictionary(s=>s.id,s=>Own(new AnimatorState {name=s.name}));
            var blends=graph.blends.ToDictionary(b=>b.id,b=>Own(new BlendTree {name=b.name}));
            var additiveBlends=graph.blends.Where(b=>additiveStates.Count>0).ToDictionary(b=>b.id,b=>Own(new BlendTree {name=b.name+" / additive"}));
            Motion Resolve(string id,bool additive=false)
            {
                if(string.IsNullOrEmpty(id) || id=="0")return null;
                if(clips.ContainsKey(id))return additive?AdditiveClip(id,graph.id,additivePaths):GraphClip(id);
                if(blends.TryGetValue(id,out var blend))return additive?additiveBlends[id]:blend;
                // VRChat's FX playable excludes humanoid motion. A missing SDK
                // neutral-hand proxy here must not inject a full-body pose above
                // the Gesture playable and then drop it when a face is selected.
                if((data.baselineFallbackMotions??Array.Empty<string>()).Contains(id))return additive?AdditiveClip(id,graph.id,additivePaths):graph.playable==5?neutralFX:baseline;
                throw new Exception("AVATAR_MOTION_DEPENDENCY_MISSING: "+id);
            }
            foreach(var b in graph.blends)
            {
                foreach(bool additive in additiveStates.Count>0?new[]{false,true}:new[]{false}) {
                    var tree=additive?additiveBlends[b.id]:blends[b.id];tree.blendType=(BlendTreeType)b.kind;tree.blendParameter=b.x;tree.blendParameterY=b.y;tree.useAutomaticThresholds=false;tree.minThreshold=b.minimum;tree.maxThreshold=b.maximum;
                    tree.children=b.children.Select(c=>new ChildMotion {motion=Resolve(c.motion,additive),threshold=c.threshold,position=new Vector2(c.x,c.y),timeScale=c.speed,cycleOffset=c.cycle,mirror=c.mirror,directBlendParameter=c.parameter}).ToArray();
                }
            }
            foreach(var s in graph.states)
            {
                var state=states[s.id];state.motion=Resolve(s.motion,additiveStates.Contains(s.id));state.speed=s.speed;state.cycleOffset=s.cycle;state.writeDefaultValues=s.writeDefaults;state.mirror=s.mirror;
                state.timeParameter=s.timeParameter;state.timeParameterActive=!string.IsNullOrEmpty(s.timeParameter);state.speedParameter=s.speedParameter;state.speedParameterActive=!string.IsNullOrEmpty(s.speedParameter);
                if(s.behaviors?.Length>0)state.AddStateMachineBehaviour<AvatarStateBehavior>().operations=s.behaviors;
            }
            // A neutral hand proxy in FX means this expression layer releases
            // the face. Fade its contribution instead of letting an empty state
            // mask the opposite hand until the last frame of the transition.
            if(graph.playable==5)
            {
                var machineSpecs=graph.machines.ToDictionary(m=>m.id);
                IEnumerable<string> LayerStates(string id) => machineSpecs[id].states.Concat(machineSpecs[id].children.SelectMany(LayerStates));
                var adapted=new HashSet<string>();
                foreach(var layer in graph.layers)
                {
                    var ids=new HashSet<string>(LayerStates(layer.root));
                    var layerStates=graph.states.Where(s=>ids.Contains(s.id)).ToArray();
                    if(!layerStates.Any(s=>(data.baselineFallbackMotions??Array.Empty<string>()).Contains(s.motion)))continue;
                    if(!graph.transitions.Any(t=>ids.Contains(t.target) && t.conditions.Any(c=>conversationalParameters.Contains(c.parameter))))continue;
                    foreach(var s in layerStates.Where(s=>adapted.Add(s.id)))
                        states[s.id].AddStateMachineBehaviour<AvatarStateBehavior>().operations=new[]{new AvatarBehavior {
                            kind="host-expression-weight",weight=(data.baselineFallbackMotions??Array.Empty<string>()).Contains(s.motion)?0:1}};
                }
            }
            foreach(var m in graph.machines)
            {
                var machine=machines[m.id];machine.states=m.states.Select(id=>new ChildAnimatorState {state=states[id]}).ToArray();machine.stateMachines=m.children.Select(id=>new ChildAnimatorStateMachine {stateMachine=machines[id]}).ToArray();
                if(states.TryGetValue(m.@default,out var state))machine.defaultState=state;
            }
            var transitions=graph.transitions.ToDictionary(t=>t.id);
            void Configure(AnimatorTransitionBase native,Transition source)
            {
                native.mute=source.muted;native.solo=source.solo;
                foreach(var condition in source.conditions)native.AddCondition((AnimatorConditionMode)condition.mode,condition.threshold,condition.parameter);
                if(native is AnimatorStateTransition t) {
                    t.duration=source.duration;t.offset=source.offset;t.exitTime=source.exitTime;t.hasExitTime=source.hasExitTime;t.hasFixedDuration=source.fixedDuration;t.interruptionSource=(TransitionInterruptionSource)source.interrupt;t.orderedInterruption=source.ordered;t.canTransitionToSelf=source.self;
                    // Close-up conversation needs a perceptible blend for the
                    // approved AI expression/gesture controls. Preserve timed
                    // choreography, longer author transitions, and outfit logic.
                    if((graph.playable==3 || graph.playable==5) && source.conditions.Any(c=>conversationalParameters.Contains(c.parameter))) {
                        float originSeconds=source.fixedDuration?source.duration:source.duration*(clips.TryGetValue(graph.states.FirstOrDefault(s=>s.transitions.Contains(source.id))?.motion??"",out var origin)?origin.length:1);
                        if(originSeconds<AvatarControlDriver.ConversationBlendSeconds){t.hasFixedDuration=true;t.duration=AvatarControlDriver.ConversationBlendSeconds;}
                    }
                }
            }
            foreach(var s in graph.states)foreach(string id in s.transitions)
            {
                var t=transitions[id];var state=states[s.id];var native=t.exit?state.AddExitTransition():states.TryGetValue(t.target,out var target)?state.AddTransition(target):machines.TryGetValue(t.machine,out var machine)?state.AddTransition(machine):null;
                if(native)Configure(native,t);
            }
            foreach(var m in graph.machines)
            {
                var machine=machines[m.id];
                foreach(string id in m.any) {var t=transitions[id];var native=states.TryGetValue(t.target,out var target)?machine.AddAnyStateTransition(target):machines.TryGetValue(t.machine,out var targetMachine)?machine.AddAnyStateTransition(targetMachine):null;if(native)Configure(native,t);}
                foreach(string id in m.entry) {var t=transitions[id];var native=states.TryGetValue(t.target,out var target)?machine.AddEntryTransition(target):machines.TryGetValue(t.machine,out var targetMachine)?machine.AddEntryTransition(targetMachine):null;if(native)Configure(native,t);}
                foreach(var link in m.machineTransitions??Array.Empty<MachineLink>())foreach(string id in link.transitions)
                {
                    var t=transitions[id];var origin=machines[link.machine];
                    var native=t.exit?machine.AddStateMachineExitTransition(origin):states.TryGetValue(t.target,out var target)?machine.AddStateMachineTransition(origin,target):machines.TryGetValue(t.machine,out var targetMachine)?machine.AddStateMachineTransition(origin,targetMachine):null;
                    if(native)Configure(native,t);
                }
            }
            var indices=new List<int>();var defaults=new List<float>();
            foreach(var l in graph.layers)
            {
                if(l.synced!=-1)throw new Exception("AVATAR_SYNCED_LAYER_REQUIRES_ADAPTER");
                int index=controller.layers.Length;indices.Add(index);
                var weight=indices.Count==1?1:l.weight;
                defaults.Add(weight);
                if(graph.playable==4 || graph.playable>=6)weight=0;
                controller.AddLayer(new AnimatorControllerLayer {name=graph.playable+" / "+l.name,defaultWeight=weight,blendingMode=l.additive?AnimatorLayerBlendingMode.Additive:AnimatorLayerBlendingMode.Override,stateMachine=machines[l.root],avatarMask=masks.TryGetValue(l.mask,out var mask)?mask:null});
            }
            groups.Add(new AvatarLayerGroup {playable=graph.playable,layers=indices.ToArray(),initialWeights=defaults.ToArray(),initialWeight=graph.playable==4 || graph.playable>=6?0:1});
        }
        var animator=root.gameObject.AddComponent<Animator>();animator.runtimeAnimatorController=controller;animator.cullingMode=AnimatorCullingMode.AlwaysAnimate;animator.applyRootMotion=false;
        var driver=character.AddComponent<AvatarControlDriver>();driver.animator=animator;driver.profile=new AvatarControlProfile {parameters=data.parameters,controls=data.controls};driver.layerGroups=groups.ToArray();
        var continuity=character.GetComponent<AvatarPoseContinuity>()??character.AddComponent<AvatarPoseContinuity>();
        continuity.bones=motions.motions.SelectMany(m=>m.tracks).Select(t=>t.path).Distinct().Select(p=>string.IsNullOrEmpty(p)?root:root.Find(p)).Where(t=>t).Select(t=>new AvatarPoseContinuity.Bone {target=t}).ToArray();
        continuity.morphs=root.GetComponentsInChildren<SkinnedMeshRenderer>(true).Where(s=>s.sharedMesh).SelectMany(s=>Enumerable.Range(0,s.sharedMesh.blendShapeCount).Select(i=>new AvatarPoseContinuity.Morph {skin=s,index=i})).ToArray();
        driver.conversationalParameters=conversationalParameters.ToArray();driver.continuity=continuity;
        var armFollow=character.GetComponent<AvatarArmFollow>()??character.AddComponent<AvatarArmFollow>();
        armFollow.joints=new[]{"LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand"}.Select(name=>{
            var human=geometry.human.FirstOrDefault(h=>h.human==name);
            return new AvatarArmFollow.Joint {bone=human==null?null:root.Find(human.path),limit=name.EndsWith("UpperArm")?3:name.EndsWith("LowerArm")?4:1.8f};
        }).Where(j=>j.bone).ToArray();
        driver.Reset();EditorUtility.SetDirty(controller);
    }
    static AnimationCurve Linear(float[] times,float[] values) {
        var curve=new AnimationCurve(times.Select((time,i)=>new Keyframe(time,values[i])).ToArray());
        for(int i=0;i<times.Length;i++){AnimationUtility.SetKeyLeftTangentMode(curve,i,AnimationUtility.TangentMode.Linear);AnimationUtility.SetKeyRightTangentMode(curve,i,AnimationUtility.TangentMode.Linear);}
        return curve;
    }
}
