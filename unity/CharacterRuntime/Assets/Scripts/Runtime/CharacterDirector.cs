using System;
using System.Collections.Generic;
using UnityEngine;
namespace ModelSpace
{
    // A bounded, data-only semantic scheduler. No package code or dialogue text is evaluated.
    public sealed class CharacterDirector : MonoBehaviour
    {
        sealed class Pending { public CharacterCue cue; public int priority; public float due,intensity; public string turn; public bool headTouch; }
        struct Lease { public int priority; public float until; }
        readonly List<Pending> pending=new List<Pending>(64);
        readonly Dictionary<string,Lease> leases=new Dictionary<string,Lease>();
        readonly Dictionary<string,float> cooldowns=new Dictionary<string,float>();
        readonly HashSet<string> seen=new HashSet<string>();
        readonly Queue<string> seenOrder=new Queue<string>();
        CharacterActions actions; CompanionAvatarDriver speech; CharacterGaze gaze;
        CharacterExpressionDriver expressions; CharacterEffectDriver effects;
        CharacterPerformanceDriver performance;
        CharacterAutonomy autonomy;
        AvatarControlDriver avatarControl;
        CharacterManifest manifest;
        int sequence,localSequence;
        string turn="";
        public Action<CharacterReceipt> OnReceipt;
        CharacterPlatformState state=new CharacterPlatformState();
        public CharacterPlatformState State { get { state.activeAction=actions?actions.CurrentAction:"";
            state.performanceSelections=performance?performance.Selections:Array.Empty<string>();
            state.avatarControlValues=avatarControl?avatarControl.Values:Array.Empty<CharacterParameterValue>();
            state.performanceTransitioning=performance && performance.Transitioning;state.autonomy=autonomy?autonomy.State:null;return state; } private set { state=value; } }
        public void ClearPerformance() { if(autonomy)autonomy.Clear();if(performance)performance.Clear(); }
        public void Bind(ViewerCharacter character,CharacterActions actionSource,CompanionAvatarDriver speechSource,CharacterGaze gazeSource)
        {
            if(autonomy)autonomy.Clear();
            if(manifest!=null) Cancel();
            manifest=character.Manifest; actions=actionSource; speech=speechSource; gaze=gazeSource;
            avatarControl=character.GetComponent<AvatarControlDriver>();
            expressions=GetComponent<CharacterExpressionDriver>() ?? gameObject.AddComponent<CharacterExpressionDriver>();
            effects=GetComponent<CharacterEffectDriver>() ?? gameObject.AddComponent<CharacterEffectDriver>();
            performance=GetComponent<CharacterPerformanceDriver>() ?? gameObject.AddComponent<CharacterPerformanceDriver>();
            expressions.Bind(character); effects.Bind(character);
            performance.Bind(character);
            autonomy=GetComponent<CharacterAutonomy>() ?? gameObject.AddComponent<CharacterAutonomy>();
            autonomy.Bind(character,performance);
            sequence=localSequence=0; turn=""; seen.Clear(); seenOrder.Clear(); cooldowns.Clear();
            State=new CharacterPlatformState { packageVersion=manifest.packageVersion,expression="neutral",effect="" };
        }
        public CharacterReceipt Receive(CharacterSignal signal) => Dispatch(signal,Time.unscaledTime,false);
        public CharacterReceipt Local(string eventName,string target="") => Dispatch(new CharacterSignal {
            actorId=manifest.id,eventId="local-"+(++localSequence),eventName=eventName,target=target,turnId=turn },Time.unscaledTime,true);
        public CharacterReceipt Dispatch(CharacterSignal s,float now,bool local=false)
        {
            var receipt=new CharacterReceipt { eventId=s?.eventId ?? "",eventName=s?.eventName ?? "",status="accepted",code="OK" };
            string invalid=s==null ? "SIGNAL_MISSING" : s.apiMajor!=1 ? "API_MAJOR_UNSUPPORTED" : s.actorId!=manifest.id ? "ACTOR_MISMATCH" :
                string.IsNullOrEmpty(s.eventId) || s.eventId.Length>128 || string.IsNullOrEmpty(s.eventName) || s.eventName.Length>96 ? "SIGNAL_INVALID" :
                !Finite(s.intensity) || !Finite(s.level) || !Finite(s.audioTime) || s.intensity<0 || s.intensity>1 || s.level<0 || s.level>1 || s.audioTime<0 ? "SIGNAL_RANGE" :
                seen.Contains(s.eventId) ? "DUPLICATE_EVENT" : !local && s.sequence<=sequence ? "STALE_SEQUENCE" :
                s.eventName!="turn.begin" && !string.IsNullOrEmpty(s.turnId) && s.turnId!=turn ? "STALE_TURN" : null;
            if(invalid!=null) { receipt.status="rejected"; receipt.code=invalid; State.rejected++; return Finish(receipt); }
            if(s.visemes!=null && (s.visemes.Length>16 || Array.Exists(s.visemes,v=>v==null || string.IsNullOrEmpty(v.id) || !Finite(v.weight) || v.weight<0 || v.weight>1)))
            { receipt.status="rejected"; receipt.code="VISEME_INVALID"; State.rejected++; return Finish(receipt); }
            if(!local) sequence=s.sequence;
            seen.Add(s.eventId); seenOrder.Enqueue(s.eventId); if(seenOrder.Count>256) seen.Remove(seenOrder.Dequeue());
            State.accepted++;
            switch(s.eventName)
            {
                case "turn.begin":
                    if(string.IsNullOrEmpty(s.turnId)) { receipt.status="rejected"; receipt.code="TURN_ID_REQUIRED"; break; }
                    Cancel(); turn=s.turnId; State.turnId=turn; break;
                case "turn.cancel": case "session.leave":
                    Cancel(); turn=""; State.turnId=""; break;
                case "speech.frame":
                    if(speech.SetSpeech(s.audioTime,s.level,s.visemes)) receipt.executed++; else { receipt.status="rejected"; receipt.code="STALE_AUDIO"; }
                    // Audio frames never cross back into the host (no mesh bake / JSON per audio sample).
                    State.lastEvent=s.eventName; return receipt;
                case "state.listening": case "state.thinking": case "state.speaking": case "state.idle":
                    speech.SetState(s.eventName.Substring(6)); break;
                case "action.request":
                    var action=Array.Find(manifest.actions,a=>a.id==s.target || a.semantic==s.target);
                    if(action==null || action.id=="Idle") { receipt.status="degraded"; receipt.code="ACTION_UNAVAILABLE"; receipt.skipped++; }
                    else if(!actions.CanPlay(action.id)) { receipt.status="degraded"; receipt.code="POSTURE_ACTION_UNAVAILABLE_OR_TRANSITIONING";receipt.skipped++; }
                    else Queue(new CharacterCue { channel="body",target=action.id,intensity=1 },80,s,now,receipt);
                    break;
                case "posture.set":
                    string postureError=actions.Posture.Validate(s.posture);
                    receipt.channel="posture";receipt.target=s.posture?.id;
                    if(postureError!=null) { receipt.status="rejected";receipt.code=postureError; }
                    else {
                        pending.RemoveAll(p=>p.cue.channel=="body" || p.cue.channel=="posture");leases.Remove("body");
                        actions.Posture.Configure(s.posture);receipt.executed++;
                    }
                    return Finish(receipt);
                case "expression.request": Queue(new CharacterCue { channel="expression",target=s.target,fallback="neutral",duration=2 },50,s,now,receipt); break;
                case "effect.request": Queue(new CharacterCue { channel="effect",target=s.target,duration=2 },50,s,now,receipt); break;
                case "performance.select": case "performance.reset":
                    receipt.channel="performance";receipt.target=s.target;
                    string performanceError=s.eventName=="performance.select" ? performance.Select(s.target,s.intensity) : performance.Reset(s.target);
                    if(performanceError!=null) {receipt.status="rejected";receipt.code=performanceError;}
                    else receipt.executed++;
                    return Finish(receipt);
            }
            bool matched=false;
            foreach(var rule in manifest.behaviors)
            {
                if(rule.eventName!=s.eventName || (!string.IsNullOrEmpty(rule.emotion) && rule.emotion!=s.emotion) || s.intensity<rule.minIntensity) continue;
                matched=true;
                if(cooldowns.TryGetValue(rule.id,out float until) && until>now) { receipt.skipped++; receipt.code="COOLDOWN"; continue; }
                if(UnityEngine.Random.value>rule.probability) { receipt.skipped++; continue; }
                cooldowns[rule.id]=now+rule.cooldown;
                foreach(var cue in rule.cues) Queue(cue,rule.priority,s,now,receipt);
            }
            if(!matched && receipt.executed==0 && receipt.skipped==0 && !s.eventName.StartsWith("state.") && !s.eventName.StartsWith("turn.") && s.eventName!="session.leave")
            { receipt.status="ignored"; receipt.code="NO_RULE"; }
            return Finish(receipt);
        }
        void Queue(CharacterCue cue,int priority,CharacterSignal signal,float now,CharacterReceipt receipt)
        {
            if(pending.Count>=64) { receipt.skipped++; receipt.status="degraded"; receipt.code="QUEUE_FULL"; return; }
            var p=new Pending { cue=cue,priority=priority,due=now+cue.delay,intensity=cue.intensity*signal.intensity,turn=signal.turnId,
                headTouch=signal.eventName=="interaction.head.tap" && cue.channel=="body" && cue.target=="No" };
            if(cue.delay<=0) { if(Execute(p,now)) receipt.executed++; else { receipt.skipped++; receipt.status="degraded"; receipt.code="CUE_UNAVAILABLE_OR_BUSY"; } }
            else { pending.Add(p); receipt.executed++; }
        }
        bool Available(string channel,string target)
        {
            switch(channel) {
                case "body": return target!="Idle" && manifest.Action(target)!=null && actions.CanPlay(target);
                case "posture": return manifest.posture!=null && Array.Exists(manifest.posture.poses,p=>p.id==target);
                case "expression": return (manifest.Supports("core.expression@1") || manifest.expressions.Length>0) &&
                    (target=="neutral" || Array.Exists(manifest.expressions,e=>e.id==target));
                case "effect": return Array.Exists(manifest.effects,e=>e.id==target);
                case "gaze": return gaze && gaze.State.available && (target=="camera" || target=="release");
                default:return false;
            }
        }
        bool Execute(Pending pending,float now)
        {
            var cue=pending.cue;
            // The existing portable head-touch -> No contract remains valid.
            // In this host its body cue becomes a bounded additive head reaction,
            // so a greeting, posture or dialogue gesture cannot swallow the touch.
            if(pending.headTouch)
            {
                if(!gaze.ReactToHeadTouch())return false;
                State.lastAction=cue.target;State.bodyCues++;return true;
            }
            if(leases.TryGetValue(cue.channel,out var lease) && lease.until>now && lease.priority>pending.priority) return false;
            var target=Available(cue.channel,cue.target)?cue.target:cue.fallback;
            if(!Available(cue.channel,target)) return false;
            float duration=cue.duration;
            switch(cue.channel) {
                case "body": actions.Play(target,"semantic"); duration=actions.Duration(target); State.lastAction=target; State.bodyCues++; break;
                case "expression": expressions.Set(target,pending.intensity); State.expression=target; State.expressionCues++; break;
                case "effect": effects.Play(Array.Find(manifest.effects,e=>e.id==target),pending.intensity); State.effect=target; State.effectCues++; break;
                case "gaze": gaze.Attention=target=="release"?0:1; break;
                case "posture":
                    actions.Posture.Configure(new PostureRequest {id=target});leases.Remove("body");break;
            }
            leases[cue.channel]=new Lease { priority=pending.priority,until=now+duration }; return true;
        }
        public void Tick(float now)
        {
            for(int i=0;i<pending.Count;)
            {
                var p=pending[i];
                if(p.due>now) { i++; continue; }
                pending.RemoveAt(i);
                if(string.IsNullOrEmpty(p.turn) || p.turn==turn) Execute(p,now);
            }
            if(leases.TryGetValue("expression",out var e) && now>=e.until) { leases.Remove("expression"); expressions.Set("neutral",0); State.expression="neutral"; }
            if(leases.TryGetValue("gaze",out var g) && now>=g.until) { leases.Remove("gaze"); gaze.Attention=1; }
            if(leases.TryGetValue("effect",out var fx) && now>=fx.until) { leases.Remove("effect"); State.effect=""; }
        }
        void Update() { if(manifest!=null) Tick(Time.unscaledTime); }
        void Cancel()
        {
            pending.Clear(); leases.Clear(); actions?.ReturnToIdle(); expressions?.Set("neutral",0); effects?.Stop();
            speech?.SetState("idle"); speech?.SetMouth(0); if(gaze) gaze.Attention=1;
            State.expression="neutral"; State.effect="";
        }
        CharacterReceipt Finish(CharacterReceipt receipt)
        {
            State.lastEvent=receipt.eventName; State.lastStatus=receipt.status; State.lastCode=receipt.code;
            OnReceipt?.Invoke(receipt); return receipt;
        }
        static bool Finite(float value) => !float.IsNaN(value) && !float.IsInfinity(value);
    }
}
