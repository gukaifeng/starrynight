using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class EmotionVariant {
        public string id,label,@base,expression,secondary;
        public float duration,finger,stance;public string[] channels;
    }
    [Serializable] public sealed class EmotionEntry {
        public string id,kind,label,providerTag;public string[] intents;public EmotionVariant[] variants;
    }
    [Serializable] public sealed class EmotionCatalog {
        public int schemaVersion,revision;public string model;public EmotionEntry[] entries;
    }
    [Serializable] public sealed class EmotionMapping {
        public string id,kind,label;public string[] variants,faces,originalOptions,channels,unavailable;
    }
    public static class EmotionPerformanceStandard {
        static EmotionCatalog catalog;
        public static EmotionCatalog Catalog {get {
            if(catalog!=null)return catalog;
            var asset=Resources.Load<TextAsset>("EmotionPerformanceStandard");
            if(!asset)throw new InvalidOperationException("EMOTION_STANDARD_MISSING");
            catalog=JsonUtility.FromJson<EmotionCatalog>(asset.text);
            if(catalog.schemaVersion!=1 || catalog.entries.Length!=42 || catalog.entries.Any(e=>e.variants.Length!=3) ||
               catalog.entries.SelectMany(e=>e.variants).Select(v=>v.id).Distinct().Count()!=126)
                throw new InvalidOperationException("EMOTION_STANDARD_INVALID");
            return catalog;
        }}
        public static EmotionEntry Entry(string kind,string id)=>Array.Find(Catalog.entries,e=>e.kind==kind && e.id==id);
        public static EmotionVariant Variant(string id)=>Catalog.entries.SelectMany(e=>e.variants).FirstOrDefault(v=>v.id==id);
        public static string Choose(string kind,string id,string previousBase,string previousKind="") {
            var e=Entry(kind,id)??Entry("emotion","neutral");
            var choices=e.variants.Where(v=>v.@base!=previousBase && v.@base!=previousKind).ToArray();
            return choices[UnityEngine.Random.Range(0,choices.Length)].id;
        }
        public static HostEmotionGesture Gesture(string id) {
            var v=Variant(id);if(v==null)return null;
            var b=Array.Find(HostEmotionGestureLibrary.Catalog.gestures,g=>g.id==v.@base);
            return new HostEmotionGesture {id=v.id,label=v.label,group=b.group,expression=v.expression,secondary=v.secondary,
                c=(float[])b.c.Clone(),duration=v.duration,face=b.face,nod=b.nod,shake=b.shake,wave=b.wave,beats=b.beats,
                finger=v.finger,stance=v.stance};
        }
        public static HostEmotionRig.Face Face(HostEmotionRig rig,string requested) {
            var exact=Array.Find(rig.faces,f=>f.gesture==requested);if(exact!=null)return exact;
            string[] fallback=requested=="sad"?new[]{"pout","curious"}:requested=="pout" || requested=="disagree"?new[]{"sad","curious"}:
                requested=="surprised"?new[]{"curious","happy"}:requested=="shy"?new[]{"happy","agree"}:new[]{"agree","happy"};
            return fallback.Select(k=>Array.Find(rig.faces,f=>f.gesture==k)).FirstOrDefault(f=>f!=null);
        }
        public static CharacterPerformanceOption[] Original(ViewerCharacter actor,EmotionEntry entry) {
            return (actor.Manifest?.performance?.options??Array.Empty<CharacterPerformanceOption>())
                .Where(o=>o.ai!=null && o.ai.automatic && o.ai.speechCompatible && o.ai.kind!="expression" && o.ai.kind!="pose" && o.kind!="toggle" && !o.loop && o.group!="expression" && o.group!="pose" &&
                    (entry.intents.Contains(o.ai.intent) || (o.ai.moods??Array.Empty<string>()).Contains(entry.id)))
                .GroupBy(o=>o.group).Select(g=>g.First()).ToArray();
        }
        public static EmotionMapping[] Map(ViewerCharacter actor,HostEmotionRig rig) {
            var secondary=actor.GetComponent<AvatarSecondaryMotion>();
            var names=(rig.joints??Array.Empty<HostEmotionRig.Joint>()).Concat(rig.naturalJoints??Array.Empty<HostEmotionRig.Joint>()).Select(j=>j.human).ToArray();
            return Catalog.entries.Select(e=> {
                var original=Original(actor,e);var channels=new List<string>(new[]{"head","torso","shoulders","arms","wrists"});
                if(names.Any(n=>n.EndsWith("Proximal")))channels.Add("fingers");
                if(rig.leftFoot && rig.rightFoot)channels.AddRange(new[]{"hips","legs","feet"});
                if(rig.faces.Length>0)channels.Add("face");
                foreach(var option in original)channels.Add(option.group);
                if(secondary && secondary.strands.Length>0)channels.Add("secondary physics (hair/clothing/accessories as authored)");
                var absent=new[]{"ears","tail","accessories"}.Where(k=>!original.Any(o=>o.group==k || o.ai.intent.StartsWith(k=="ears"?"ear_":k=="tail"?"tail_":"accessory_"))).ToArray();
                return new EmotionMapping {id=e.id,kind=e.kind,label=e.label,variants=e.variants.Select(v=>v.id).ToArray(),
                    faces=e.variants.Select(v=> {var face=Face(rig,v.expression);return face==null?"neutral (unavailable)":face.label+(face.gesture==v.expression?"":" (fallback)");}).ToArray(),
                    originalOptions=original.Select(o=>o.id+" · "+o.label).ToArray(),channels=channels.Distinct().ToArray(),unavailable=absent};
            }).ToArray();
        }
    }
}
