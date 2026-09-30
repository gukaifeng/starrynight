using System;
using System.IO;
using System.Linq;
using UnityEngine;
using UnityEditor.SceneManagement;
using ModelSpace;

// Numeric checks on disposable instances. Does not claim device frame-rate or
// manufacture character motion; the new-group probe reuses actual source clips.
public static class ExpressiveConversationReview
{
    static int assertions;
    static void Check(bool value,string reason) {if(!value)throw new Exception("EXPRESSIVE_REVIEW: "+reason);assertions++;}
    static void Wait(CharacterPreviewRotation p,float seconds) {for(int i=0;i<Mathf.CeilToInt(seconds*60);i++)p.Step(1f/60);}
    static bool Shake(CharacterPreviewRotation p,bool accept=true) {
        int before=p.ShakeCount;p.Begin();
        // About +/- 30 points on a 393-point phone, two gentle direction changes.
        for(int i=0;i<60;i++) {p.Move(.08f*Mathf.Sin(i/59f*Mathf.PI*3),0);p.Step(1f/60);}
        p.End(accept);return p.ShakeCount>before;
    }
    public static void Run()
    {
        assertions=0;
        var preview=new CharacterPreviewRotation();
        preview.Begin();preview.Move(.2f,0);Wait(preview,1);
        Check(!preview.End(true),"ordinary one-way rotation must not complain");Wait(preview,1);
        preview.Begin();for(int i=0;i<120;i++) {preview.Move(i%2==0?.002f:-.002f,0);preview.Step(1f/60);}
        Check(!preview.End(true),"tiny jitter must not accumulate into a shake");
        Check(Shake(preview),"small 30-point back-and-forth gesture causes a reaction");
        Check(preview.ShakeCount==1 && preview.ShakeIntensity>=.5f,"bounded intensity and single emission");
        Wait(preview,2);Check(preview.Offset==Vector2.zero,"temporary gesture still restores exactly");
        Check(!Shake(preview),"repeated shaking is cooled down");
        Wait(preview,21);preview.Begin();preview.Move(.08f,0);preview.End(false);
        Check(preview.ShakeCount==1,"cancel before threshold cannot react");
        Check(Shake(preview) && preview.ShakeCount==2,"valid interaction works after cooldown");
        preview.Reset();preview.Begin();preview.Move(4,4);Wait(preview,2);
        for(int i=0;i<5;i++) {preview.Move(4+i,4+i);Wait(preview,.2f);}
        Check(!preview.End(true),"dragging beyond the clamp does not count imaginary movement");
        preview.Reset();Check(preview.ShakeCount==0 && !preview.Active,"actor reset clears interaction state");
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var source in viewer.characters.Where(c=>!c.Manifest.Supports("core.avatar-controls@1"))) {
            var instance=UnityEngine.Object.Instantiate(source.gameObject);instance.SetActive(true);
            var host=new GameObject("ExpressiveReviewDriver");
            try {
                var character=instance.GetComponent<ViewerCharacter>();character.ApplyContract();
                var profile=character.Manifest.performance;
                var player=character.GetComponentInChildren<Animation>(true);
                var driver=host.AddComponent<CharacterPerformanceDriver>();
                // Only the disposable parsed contract changes: prove future groups
                // receive independent layers, using each avatar's real ear/tail clips.
                profile.schemaVersion=2;
                foreach(string old in new[]{"ears","tail"}) {
                    string id="author."+old;
                    profile.groups.First(g=>g.id==old).id=id;
                    foreach(var option in profile.options.Where(o=>o.group==old))option.group=id;
                }
                CharacterPerformanceContract.Validate(profile);driver.Bind(character);
                var options=new[]{"expression","hands","author.ears","author.tail"}.Select(g=>profile.options.First(o=>o.group==g && o.kind!="toggle" && (g=="expression"?o.morphs.Length>0:!string.IsNullOrEmpty(o.clip)))).ToArray();
                foreach(var option in options)Check(driver.Select(option.id,1)==null,source.modelId+" select "+option.group);
                for(int i=0;i<90;i++) {driver.RestoreMorphs();driver.Step(1f/60);foreach(AnimationState state in player)if(state.enabled)state.time+=1f/60;player.Sample();driver.ApplyFrame();}
                Check(options.All(o=>driver.Selections.Contains(o.id)),"four source groups coexist");
                var layers=player.Cast<AnimationState>().Where(s=>s.enabled && s.weight>.5f && s.layer>=10).Select(s=>s.layer).Distinct().ToArray();
                Check(layers.Length>=3,"hands and two new author groups have separate animation layers");
                foreach(var o in options)driver.Reset(o.group);
                for(int i=0;i<90;i++) {driver.RestoreMorphs();driver.Step(1f/60);driver.ApplyFrame();}
                Check(!driver.Transitioning,"group release settles smoothly");
                Check(!driver.Selections.Any(id=>options.Any(o=>o.id==id && !o.defaultOn)),"default state restored");
                driver.Clear();
            } finally {UnityEngine.Object.DestroyImmediate(host);UnityEngine.Object.DestroyImmediate(instance);}
        }
        string folder=Path.Combine(CharacterPackageBuilder.Root,".local/checks/expressive-ai");Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder,"unity-review.json"),"{\"status\":\"PASS\",\"assertions\":"+assertions+",\"scope\":\"gesture qualification and independent real animation layers; no device FPS measurement\"}\n");
        Debug.Log("EXPRESSIVE_REVIEW_PASS assertions="+assertions);
    }
}
