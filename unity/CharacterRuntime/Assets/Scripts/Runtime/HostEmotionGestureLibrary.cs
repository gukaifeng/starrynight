using System;
using System.Linq;
using UnityEngine;

namespace ModelSpace
{
    // Single host-authored catalog shared with the native developer UI. No model data.
    [Serializable] public sealed class HostEmotionGesture
    {
        public string id,label,group,expression,secondary;
        public string[] intents=Array.Empty<string>();
        public float duration,face,nod,shake,wave,finger,stance;
        public int beats=1;
        // Pitch, yaw, roll, chest, lean, twist, L/R abduction, L/R forward,
        // L/R elbow flexion and wrist accent, in anatomical degrees.
        public float[] c;
    }
    [Serializable] public sealed class HostEmotionGestureGroup {public string id,label;}
    [Serializable] public sealed class HostEmotionGestureCatalog
    {
        public int revision;
        public HostEmotionGestureGroup[] groups;
        public HostEmotionGesture[] gestures;
    }
    public static class HostEmotionGestureLibrary
    {
        static HostEmotionGestureCatalog catalog;
        public static HostEmotionGestureCatalog Catalog {
            get {
                if(catalog!=null)return catalog;
                var asset=Resources.Load<TextAsset>("HostEmotionGestures");
                if(!asset)throw new InvalidOperationException("HOST_GESTURE_CATALOG_MISSING");
                var parsed=JsonUtility.FromJson<HostEmotionGestureCatalog>(asset.text);
                if(parsed.revision!=3 || parsed.gestures==null || parsed.groups==null ||
                   parsed.gestures.Select(p=>p.id).Distinct().Count()!=parsed.gestures.Length)
                    throw new InvalidOperationException("HOST_GESTURE_CATALOG_INVALID");
                foreach(var p in parsed.gestures)
                    if(p.c==null || p.c.Length!=13 || p.c.Any(v=>!float.IsFinite(v)) || p.duration<4 || p.duration>7 ||
                       p.face<0 || p.face>1 || !parsed.groups.Any(g=>g.id==p.group))
                        throw new InvalidOperationException("HOST_GESTURE_PROFILE_INVALID: "+p.id);
                catalog=parsed;return catalog;
            }
        }
        public static HostEmotionGesture Find(string id)=>Array.Find(Catalog.gestures,p=>p.id==id)??EmotionPerformanceStandard.Gesture(id);
        public static string Normalize(string intent)
        {
            switch(intent) {
                case "surprise":return "surprised";
                case "bright_smile":return "happy";
                case "soft_smile":return "soft_smile";
                default:return intent ?? "";
            }
        }
        public static string Select(string intent,int sequence,string previous)
        {
            intent=Normalize(intent);
            var choices=Catalog.gestures.Where(p=>p.intents.Contains(intent) && p.id!=previous).ToArray();
            if(choices.Length==0)choices=Catalog.gestures.Where(p=>p.intents.Contains(intent)).ToArray();
            return choices.Length==0?"":choices[Math.Abs(sequence%choices.Length)].id;
        }
    }
}
