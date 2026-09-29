using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEngine;
using UnityEditor;
public static class CharacterPlatformReview
{
    [Serializable] sealed class Report { public string status="PASS"; public int assertions; public List<string> cases=new List<string>(); }
    static Report report;
    static void Check(bool ok,string name) { if(!ok) throw new Exception("CHARACTER_PLATFORM_REVIEW: "+name); report.assertions++; report.cases.Add(name); }
    // Run in Play Mode so real Animation crossfades, coroutines and mesh bindings execute.
    public static void Run()
    {
        if(!EditorApplication.isPlaying) throw new Exception("Enter Play Mode before CharacterPlatformReview.Run");
        report=new Report();
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        int presentation=100;
        foreach(var character in viewer.characters)
        {
            viewer.ReceiveCommand(JsonUtility.ToJson(new BridgeCommand { schemaVersion=1,kind="command",name="selectModel",presentationId=presentation++,payload=new BridgePayload { modelId=character.modelId } }));
            var director=viewer.GetComponent<CharacterDirector>(); director.enabled=false;
            var actions=viewer.GetComponent<CharacterActions>();
            // Verify normalized morphs against the actual mesh's authored range (glTF may use 1, old assets 100).
            var expressionDriver=viewer.GetComponent<CharacterExpressionDriver>();
            var restore=typeof(CharacterExpressionDriver).GetMethod("Update",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance);
            var step=typeof(CharacterExpressionDriver).GetMethod("LateUpdate",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance);
            foreach(var expression in character.Manifest.expressions)
            {
                expressionDriver.Set(expression.id,1);
                for(int frame=0;frame<120;frame++) { restore.Invoke(expressionDriver,null);step.Invoke(expressionDriver,null); }
                foreach(var binding in expression.bindings)
                {
                    var skin=CharacterContract.Resolve(character.transform,binding.renderer).GetComponent<SkinnedMeshRenderer>();
                    int shape=skin.sharedMesh.GetBlendShapeIndex(binding.shape);float weight=skin.GetBlendShapeWeight(shape);
                    Check(weight>0 && weight<=CharacterContract.MorphScale(skin,shape)+.001f,character.modelId+" morph scale "+binding.shape);
                }
                expressionDriver.Set("neutral",0);
                for(int frame=0;frame<180;frame++) { restore.Invoke(expressionDriver,null);step.Invoke(expressionDriver,null); }
                restore.Invoke(expressionDriver,null);
            }
            int seq=0;
            CharacterSignal Signal(string name,string turn="t1",string target="",string emotion="") => new CharacterSignal {
                sequence=++seq,actorId=character.modelId,eventId="review-"+seq,eventName=name,turnId=turn,target=target,emotion=emotion };
            var begin=Signal("turn.begin"); Check(director.Dispatch(begin,10).status=="accepted",character.modelId+" begin");
            Check(director.Dispatch(begin,10).code=="DUPLICATE_EVENT","dedupe");
            var stale=Signal("dialogue.reply"); stale.sequence=1;Check(director.Dispatch(stale,10).code=="STALE_SEQUENCE","out-of-order");
            var wrong=Signal("dialogue.reply"); wrong.actorId="other";Check(director.Dispatch(wrong,10).code=="ACTOR_MISMATCH","actor isolation");
            var major=Signal("dialogue.reply");major.apiMajor=2;Check(director.Dispatch(major,10).code=="API_MAJOR_UNSUPPORTED","major negotiation");
            var future=Signal("future.event");future.apiMinor=25;Check(director.Dispatch(future,10).status=="ignored","unknown optional semantic");
            var invalid=Signal("dialogue.reply");invalid.intensity=float.NaN;Check(director.Dispatch(invalid,10).code=="SIGNAL_RANGE","finite numbers");
            if(character.Manifest.Action("Wave")!=null)
            {
                Check(director.Dispatch(Signal("action.request",target:"Wave"),11).executed==1 && actions.CurrentAction=="Wave",character.modelId+" actual clip");
                var busy=director.Dispatch(Signal("dialogue.greeting"),11.1f);Check(actions.CurrentAction=="Wave" && busy.skipped>0,"body priority lease");
                Check(director.Dispatch(Signal("dialogue.greeting"),11.2f).code=="COOLDOWN","rule cooldown");
            }
            else
            {
                Check(director.Dispatch(Signal("action.request",target:"Wave"),11).code=="ACTION_UNAVAILABLE",character.modelId+" absent Wave remains unavailable");
                if(!character.Manifest.behaviors.Any(r=>r.eventName=="dialogue.greeting"))
                    Check(director.Dispatch(Signal("dialogue.greeting"),11.1f).code=="NO_RULE",character.modelId+" absent greeting has no authored motion");
            }
            Check(director.Dispatch(Signal("action.request",target:"does-not-exist"),11.3f).code=="ACTION_UNAVAILABLE","unavailable action fallback");
            director.Dispatch(Signal("dialogue.reply",emotion:"joy"),12);
            int effects=director.State.effectCues;
            director.Dispatch(Signal("turn.cancel"),12.1f);director.Tick(30);
            Check(director.State.effectCues==effects && actions.CurrentAction=="","cancel delayed effect and body");
            Check(director.Dispatch(Signal("dialogue.reply"),31).code=="STALE_TURN","stale cancelled turn");
            director.Dispatch(Signal("turn.begin","t2"),32);
            director.Dispatch(Signal("dialogue.reply","t2",emotion:"care"),33);
            if(character.Manifest.effects.Any(e=>e.id=="care"))Check(director.State.effect=="care",character.modelId+" mapped effect");
            else Check(director.State.effect=="",character.modelId+" no invented care effect");
            if(character.Manifest.expressions.Any(e=>e.id=="care")) Check(director.State.expression=="care",character.modelId+" mapped expression");
            director.Tick(36); Check(director.State.expression=="neutral","expression release");
            var audio=Signal("speech.frame","t2");audio.audioTime=2;audio.level=.5f;Check(director.Dispatch(audio,37).executed==1,"speech frame");
            audio=Signal("speech.frame","t2");audio.audioTime=1;Check(director.Dispatch(audio,37).code=="STALE_AUDIO","audio ordering");
            var hostile=JsonUtility.FromJson<CharacterManifest>(character.contractAsset.text);
            hostile.compatibility.required=new[]{"future.physics@99"};bool refused=false;
            try { CharacterContract.Validate(hostile); } catch(ArgumentException) { refused=true; }
            Check(refused,"unknown required capability rejected");
            director.Dispatch(Signal("session.leave",""),38); director.enabled=true;
        }
        string path=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/character-platform/engine-review.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,JsonUtility.ToJson(report,true));
        Debug.Log("CHARACTER_PLATFORM_REVIEW_PASS assertions="+report.assertions);
    }
}
