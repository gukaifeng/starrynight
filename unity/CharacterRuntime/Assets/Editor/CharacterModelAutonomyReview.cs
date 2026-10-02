using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEngine;

// Exercise the actual runtime facial layer and authored tracking overrides.
// A manually posed eyelid screenshot alone does not prove automatic blinking.
public static class CharacterModelAutonomyReview
{
    public static void RunPrepared()
    {
        UnityEditor.SceneManagement.EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        Validate(UnityEngine.Object.FindFirstObjectByType<ViewerController>());
    }
    [Serializable] sealed class Check {
        public string id;public int frames,hostBlinkCount;
        public bool authoredAllowsBlink;
        public float hostBlinkMaximum;
        public float[] eyelidRanges;
        public string[] authoredEyelids;
        public float[] authoredEyelidRanges;
    }
    [Serializable] sealed class Report {public string scope="Unity runtime methods on prepared scene; device not certified";public Check[] characters;}
    public static void Validate(ViewerController viewer)
    {
        var checks=new System.Collections.Generic.List<Check>();
        bool[] active=viewer.characters.Select(c=>c.gameObject.activeSelf).ToArray();
        try {
            foreach(var character in viewer.characters.Where(c=>CharacterAutonomyContract.Supported(c.Manifest))) {
                foreach(var other in viewer.characters)other.gameObject.SetActive(other==character);
                var bindings=character.Manifest.autonomy.blink.bindings;
                var skins=bindings.Select(b=>CharacterContract.Resolve(character.transform,b.renderer).GetComponent<SkinnedMeshRenderer>()).ToArray();
                var indices=bindings.Select((b,i)=>skins[i].sharedMesh.GetBlendShapeIndex(b.shape)).ToArray();
                var minimum=Enumerable.Repeat(float.PositiveInfinity,bindings.Length).ToArray();
                var maximum=Enumerable.Repeat(float.NegativeInfinity,bindings.Length).ToArray();
                var player=character.GetComponent<Animation>();var idle=player.GetClip("Idle");
                var authored=character.GetComponent<AvatarControlDriver>();
                var authorLids=authored ? authored.animator.runtimeAnimatorController.animationClips
                    .SelectMany(clip=>AnimationUtility.GetCurveBindings(clip).Where(binding=>{
                        if(binding.type!=typeof(SkinnedMeshRenderer) || !binding.propertyName.StartsWith("blendShape.",StringComparison.Ordinal))return false;
                        string shape=binding.propertyName.Substring(11);
                        if(shape.IndexOf("blink",StringComparison.OrdinalIgnoreCase)<0 && !shape.Contains("まばたき"))return false;
                        var curve=AnimationUtility.GetEditorCurve(clip,binding);
                        return curve.keys.Length>1 && curve.keys.Max(k=>k.value)-curve.keys.Min(k=>k.value)>.01f;
                    })).GroupBy(b=>b.path+"/"+b.propertyName).Select(g=>g.First()).ToArray()
                    :Array.Empty<EditorCurveBinding>();
                var authorSkins=authorLids.Select(b=>authored.animator.transform.Find(b.path)?.GetComponent<SkinnedMeshRenderer>()).ToArray();
                var authorIndices=authorLids.Select((b,i)=>authorSkins[i]?authorSkins[i].sharedMesh.GetBlendShapeIndex(b.propertyName.Substring(11)):-1).ToArray();
                if(authorIndices.Any(i=>i<0))throw new Exception("MODEL_REVIEW_AUTHOR_EYELID_MISSING");
                var authorMinimum=Enumerable.Repeat(float.PositiveInfinity,authorLids.Length).ToArray();
                var authorMaximum=Enumerable.Repeat(float.NegativeInfinity,authorLids.Length).ToArray();
                if(authored){authored.Reset();authored.animator.Update(0);}
                if(character.GetComponent<CharacterAutonomy>())throw new Exception("MODEL_REVIEW_AUTONOMY_ALREADY_BOUND");
                var autonomy=character.gameObject.AddComponent<CharacterAutonomy>();
                var check=new Check {id=character.modelId,frames=480};
                try {
                    autonomy.Bind(character,character.GetComponent<CharacterPerformanceDriver>(),42);
                    for(int frame=0;frame<check.frames;frame++) {
                        autonomy.RestoreMorphs();
                        if(authored){authored.AdvanceWeights(1f/60);authored.animator.Update(1f/60);}
                        else idle.SampleAnimation(character.gameObject,(frame/60f)%Mathf.Max(idle.length,.0001f));
                        autonomy.Step(1f/60);autonomy.ApplyFrame();
                        check.hostBlinkMaximum=Mathf.Max(check.hostBlinkMaximum,autonomy.State.blinkWeight);
                        for(int i=0;i<bindings.Length;i++) {
                            float weight=skins[i].GetBlendShapeWeight(indices[i])/CharacterContract.MorphScale(skins[i],indices[i]);
                            minimum[i]=Mathf.Min(minimum[i],weight);maximum[i]=Mathf.Max(maximum[i],weight);
                        }
                        for(int i=0;i<authorLids.Length;i++) {
                            float weight=authorSkins[i].GetBlendShapeWeight(authorIndices[i])/CharacterContract.MorphScale(authorSkins[i],authorIndices[i]);
                            authorMinimum[i]=Mathf.Min(authorMinimum[i],weight);authorMaximum[i]=Mathf.Max(authorMaximum[i],weight);
                        }
                    }
                    check.hostBlinkCount=autonomy.State.blinkCount;
                    check.authoredAllowsBlink=!authored || authored.AllowBlink;
                    check.eyelidRanges=maximum.Select((value,i)=>value-minimum[i]).ToArray();
                    check.authoredEyelids=authorLids.Select(b=>b.path+"/"+b.propertyName).ToArray();
                    check.authoredEyelidRanges=authorMaximum.Select((value,i)=>value-authorMinimum[i]).ToArray();
                    checks.Add(check);
                } finally {
                    autonomy.Clear();
                    UnityEngine.Object.DestroyImmediate(character.GetComponent<CharacterAutonomyRestore>());
                    UnityEngine.Object.DestroyImmediate(autonomy);
                    if(authored){authored.Reset();authored.animator.Update(0);}
                    idle.SampleAnimation(character.gameObject,0);
                }
            }
        } finally {
            for(int i=0;i<active.Length;i++)viewer.characters[i].gameObject.SetActive(active[i]);
        }
        string path=Path.Combine(CharacterPackageBuilder.Root,".local/checks/model-review-autonomy.json");
        File.WriteAllText(path,JsonUtility.ToJson(new Report {characters=checks.ToArray()},true));
        var frozen=checks.Where(c=>c.eyelidRanges.Any(range=>!float.IsFinite(range) || range<.2f) &&
            !c.authoredEyelidRanges.Any(range=>float.IsFinite(range) && range>=.2f)).Select(c=>c.id).ToArray();
        if(frozen.Length>0)throw new Exception("MODEL_REVIEW_AUTOMATIC_BLINK_FROZEN: "+string.Join(",",frozen));
        Debug.Log("MODEL_REVIEW_AUTONOMY_PASS characters="+checks.Count);
    }
}
