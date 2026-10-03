using System;
using System.Linq;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class CharacterDisplay
    {
        public string name, originalName, description, invitation, tagline, symbol, thumbnail;
        public string cardIdentifier, openIdentifier, style;
        public float thumbnailScale=1;
        public int order=100;
    }
    [Serializable] public sealed class CharacterCompatibility
    {
        public int apiMajor=1, minApiMinor;
        public string[] required=Array.Empty<string>(), optional=Array.Empty<string>();
    }
    [Serializable] public sealed class CharacterSource
    {
        public string format, model;
        public float scale=1, yaw;
    }
    [Serializable] public sealed class CharacterRig
    {
        public string head, neck, leftEye, rightEye, headRenderer;
        public float conversationStart=.5f;
        // Authored portrait composition for very wide heads / compact bodies.
        // Optional: previous packages keep their exact framing at 1.
        public float portraitWidthScale=1;
    }
    [Serializable] public sealed class CharacterGazeLimits
    {
        public float yaw=50, up=22, down=28, eyeYaw=12, eyeUp=8, eyeDown=10;
    }
    [Serializable] public sealed class CharacterClip
    {
        public string id, clip, semantic, label, symbol, framing="full", gaze="follow";
        public bool button;
    }
    [Serializable] public sealed class ShapeBinding
    {
        public string renderer, shape;
        public float weight=1;
    }
    [Serializable] public sealed class CharacterExpression
    {
        public string id;
        public ShapeBinding[] bindings=Array.Empty<ShapeBinding>();
    }
    [Serializable] public sealed class CharacterSpeech
    {
        public string mode="none";
        // Existing characters retain the conversational accent. Source-faithful
        // imports can supply their own motion without host-authored head nods.
        public bool proceduralHeadMotion=true;
        public ShapeBinding[] amplitude=Array.Empty<ShapeBinding>();
        public CharacterExpression[] visemes=Array.Empty<CharacterExpression>();
    }
    [Serializable] public sealed class CharacterEffect
    {
        public string id, kind="sparkles", anchor="head", color="#F7C97C";
        public int count=10;
    }
    [Serializable] public sealed class CharacterInteraction
    {
        public string id, bone, renderer, eventName;
        public float radius=.08f;
    }
    [Serializable] public sealed class CharacterCue
    {
        public string channel, target, fallback;
        public float delay, duration=2, intensity=1;
        public bool required;
    }
    [Serializable] public sealed class CharacterRule
    {
        public string id, eventName, emotion;
        public int priority=30;
        public float cooldown=2, probability=1, minIntensity;
        public CharacterCue[] cues=Array.Empty<CharacterCue>();
    }
    [Serializable] public sealed class ParameterBinding
    {
        public string path, property, negativeShape;
        public int materialSlot;
    }
    [Serializable] public sealed class CharacterParameter
    {
        public string id, label, kind="morph", section="细节";
        public float min, max=1, initial=.5f;
        public string[] options=Array.Empty<string>();
        public ParameterBinding[] bindings=Array.Empty<ParameterBinding>();
    }
    [Serializable] public sealed class CharacterParameterValue { public string id; public float value; }
    [Serializable] public sealed class CharacterManifest
    {
        public int schemaVersion=1;
        public string id, packageId, packageVersion;
        public CharacterDisplay display=new CharacterDisplay();
        public CharacterCompatibility compatibility=new CharacterCompatibility();
        public CharacterSource source=new CharacterSource();
        public CharacterRig rig=new CharacterRig();
        public CharacterGazeLimits gaze=new CharacterGazeLimits();
        public CharacterSpeech speech=new CharacterSpeech();
        public CharacterClip[] actions=Array.Empty<CharacterClip>();
        public CharacterExpression[] expressions=Array.Empty<CharacterExpression>();
        public CharacterEffect[] effects=Array.Empty<CharacterEffect>();
        public CharacterInteraction[] interactions=Array.Empty<CharacterInteraction>();
        public CharacterRule[] behaviors=Array.Empty<CharacterRule>();
        public CharacterParameter[] parameters=Array.Empty<CharacterParameter>();
        public PostureProfile posture;
        public CharacterPerformanceProfile performance;
        public CharacterAutonomyProfile autonomy;
        public bool Supports(string capability) => compatibility.required.Concat(compatibility.optional).Contains(capability);
        public CharacterClip Action(string id) => Array.Find(actions,a=>a.id==id);
    }
    [Serializable] public sealed class CharacterSignal
    {
        public int apiMajor=1, apiMinor, sequence;
        public string actorId, eventId, turnId, eventName, emotion, target;
        public float intensity=1, audioTime, level;
        public VisemeValue[] visemes=Array.Empty<VisemeValue>();
        public PostureRequest posture;
        public string[] selections=Array.Empty<string>();
    }
    [Serializable] public sealed class VisemeValue { public string id; public float weight; }
    [Serializable] public sealed class CharacterReceipt
    {
        public string eventId, eventName, status, code, channel, target;
        public int executed, skipped;
        // Optional, local monotonic CPU time for validation/control dispatch.
        // Animator evaluation and GPU rendering happen later in the frame.
        public double processingMs;
        [NonSerialized] public long processingStarted;
    }
    [Serializable] public sealed class CharacterPlatformState
    {
        public int apiMajor=1, apiMinor=1;
        public string packageVersion, turnId, lastEvent, lastStatus, lastCode, expression, effect, activeAction, lastAction;
        public int accepted, rejected, bodyCues, expressionCues, effectCues;
        public string[] performanceSelections=Array.Empty<string>();
        public bool performanceTransitioning;
        public int petMode,petReactions;
        public CharacterParameterValue[] avatarControlValues=Array.Empty<CharacterParameterValue>();
        public CharacterAutonomyState autonomy;
        public HostEmotionMotionState hostEmotionMotion; // Optional host experiment, not an authored capability.
        public SourceMotionPreviewState sourceMotionPreview;
    }
    // Runtime-owned capability vocabulary. Unknown required capabilities refuse activation;
    // unknown optional capabilities degrade without breaking a character's base experience.
    public static class CharacterContract
    {
        public static readonly string[] Capabilities={"core.animation@1","core.gaze@1","core.expression@1",
            "core.speech.amplitude@1","core.speech.viseme@1","core.interaction@1","core.effects@1","core.parameters@1",
            "core.behavior@1","core.posture@1","core.secondary-motion@1","core.secondary-motion@2","core.secondary-motion@3","core.secondary-motion@4","core.avatar-controls@1","core.avatar-controls@2","core.source-motions@1","core.materials.liltoon@1","core.performance@1","core.performance@2","core.performance@3","core.autonomy@1","legacy.human-studio@1"};
        public static void Validate(CharacterManifest m)
        {
            if(m==null || m.schemaVersion!=1 || string.IsNullOrWhiteSpace(m.id)) throw new ArgumentException("CHARACTER_SCHEMA_UNSUPPORTED");
            if(m.compatibility.apiMajor!=1 || m.compatibility.minApiMinor>1) throw new ArgumentException("CHARACTER_API_UNSUPPORTED");
            foreach(var required in m.compatibility.required)
                if(!Capabilities.Contains(required)) throw new ArgumentException("CHARACTER_CAPABILITY_REQUIRED: "+required);
            if(m.gaze.yaw<=0 || m.gaze.yaw>50 || m.gaze.up<=0 || m.gaze.up>22 || m.gaze.down<=0 || m.gaze.down>28 ||
                m.gaze.eyeYaw<=0 || m.gaze.eyeYaw>12 || m.gaze.eyeUp<=0 || m.gaze.eyeUp>8 || m.gaze.eyeDown<=0 || m.gaze.eyeDown>10)
                throw new ArgumentException("CHARACTER_GAZE_LIMITS_INVALID");
            if(m.actions.Length==0 || m.Action("Idle")==null) throw new ArgumentException("CHARACTER_IDLE_REQUIRED");
            if(m.actions.Select(a=>a.id).Distinct().Count()!=m.actions.Length) throw new ArgumentException("CHARACTER_DUPLICATE_ACTION");
            CharacterPerformanceContract.Validate(m.performance);
            if(m.performance?.options.Any(o=>!string.IsNullOrEmpty(o.control?.id))==true && !m.compatibility.required.Any(c=>c=="core.avatar-controls@1" || c=="core.avatar-controls@2"))
                throw new ArgumentException("CHARACTER_CAPABILITY_REQUIRED: core.avatar-controls@1");
            if(m.performance?.schemaVersion>=2 && !m.compatibility.required.Contains("core.performance@"+m.performance.schemaVersion))
                throw new ArgumentException("CHARACTER_CAPABILITY_REQUIRED: core.performance@2");
            CharacterAutonomyContract.Validate(m);
        }
        public static float MorphScale(SkinnedMeshRenderer skin,int index) => skin.sharedMesh.GetBlendShapeFrameWeight(index,skin.sharedMesh.GetBlendShapeFrameCount(index)-1);
        public static string ColorProperty(Material material,string property) => property=="baseColor" ? (material.HasProperty("baseColorFactor")?"baseColorFactor":"_BaseColor") : property;
        public static Transform Resolve(Transform root,string path) => string.IsNullOrEmpty(path)?null:root.Find(path);
    }
}
