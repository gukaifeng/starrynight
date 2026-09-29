using System;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEngine;

// Conversion owns the source-controller interpretation. This boundary only accepts
// explicit renderer/morph bindings and transform-only, already-baked clips.
public static class CharacterPerformanceBuilder
{
    public static void Prepare(ViewerCharacter character,AnimationClip[] importedClips)
    {
        var profile=character.Manifest.performance;if(profile==null)return;
        var player=character.GetComponentInChildren<Animation>(true);
        foreach(string name in profile.Clips)
        {
            var clip=importedClips.FirstOrDefault(c=>c.name==name);
            if(!clip || !clip.legacy)throw new Exception("PERFORMANCE_CLIP_MISSING: "+name);
            if(player.GetClip(name) && player.GetClip(name)!=clip)throw new Exception("PERFORMANCE_CLIP_CONFLICT: "+name);
            player.AddClip(clip,name);
        }
        Validate(character);
        foreach(var value in profile.defaults)SetVisible(character,value);
        foreach(var option in profile.options)
        {
            foreach(var value in option.defaultOn?option.visibility:option.offVisibility)SetVisible(character,value);
            foreach(var value in option.defaultOn?option.morphs:option.offMorphs)
            {
                var skin=CharacterContract.Resolve(character.transform,value.renderer).GetComponent<SkinnedMeshRenderer>();
                int index=skin.sharedMesh.GetBlendShapeIndex(value.shape);
                skin.SetBlendShapeWeight(index,value.weight*CharacterContract.MorphScale(skin,index));
            }
        }
    }
    static void SetVisible(ViewerCharacter character,CharacterVisibility value)
        => CharacterContract.Resolve(character.transform,value.path).GetComponent<Renderer>().enabled=value.visible;
    public static void Validate(ViewerCharacter character)
    {
        var profile=character.Manifest.performance;if(profile==null)return;
        CharacterPerformanceContract.Validate(profile);
        var root=character.transform;var player=character.GetComponentInChildren<Animation>(true);
        Transform Resolve(string path)
        {
            var t=CharacterContract.Resolve(root,path);
            if(!t)throw new Exception("PERFORMANCE_PATH_MISSING: "+character.modelId+"/"+path);return t;
        }
        void Visible(CharacterVisibility value)
        {
            var renderer=Resolve(value.path).GetComponent<Renderer>();
            if(!renderer)throw new Exception("PERFORMANCE_RENDERER_MISSING: "+value.path);
            if(!value.visible && value.path==character.Manifest.rig.headRenderer)
                throw new Exception("PERFORMANCE_HIDES_REQUIRED_FACE: "+value.path);
        }
        foreach(var value in profile.defaults)Visible(value);
        foreach(var option in profile.options)
        {
            foreach(var binding in option.morphs.Concat(option.offMorphs).Concat(option.morphTracks.Select(t=>new ShapeBinding {renderer=t.renderer,shape=t.shape})))
            {
                var skin=Resolve(binding.renderer).GetComponent<SkinnedMeshRenderer>();
                int index=skin?skin.sharedMesh.GetBlendShapeIndex(binding.shape):-1;
                if(index<0 || !float.IsFinite(CharacterContract.MorphScale(skin,index)) || CharacterContract.MorphScale(skin,index)<=0)
                    throw new Exception("PERFORMANCE_MORPH_MISSING: "+option.id+"/"+binding.renderer+"/"+binding.shape);
            }
            foreach(var value in option.visibility.Concat(option.offVisibility))Visible(value);
            foreach(string bone in option.bones)Resolve(bone);
            foreach(string clipName in new[]{option.clip,option.offClip}.Where(c=>!string.IsNullOrEmpty(c)).Distinct())
            {
            var clip=player?player.GetClip(clipName):null;
            if(!clip || !clip.legacy || !float.IsFinite(clip.length) || clip.length>120)
                throw new Exception("PERFORMANCE_CLIP_INVALID: "+option.id);
            if(AnimationUtility.GetAnimationEvents(clip).Length>0 || AnimationUtility.GetObjectReferenceCurveBindings(clip).Length>0)
                throw new Exception("PERFORMANCE_CLIP_EXECUTABLE_OR_OBJECT_DATA: "+option.id);
            var bindings=AnimationUtility.GetCurveBindings(clip);
            if(bindings.Length==0)throw new Exception("PERFORMANCE_CLIP_EMPTY: "+option.id);
            foreach(var binding in bindings)
            {
                string property=binding.propertyName.Replace("m_","");
                if(binding.type!=typeof(Transform) || !option.bones.Contains(binding.path) ||
                    !(property.StartsWith("localPosition.",StringComparison.OrdinalIgnoreCase) || property.StartsWith("localRotation.",StringComparison.OrdinalIgnoreCase) ||
                      property.StartsWith("localScale.",StringComparison.OrdinalIgnoreCase)))
                    throw new Exception("PERFORMANCE_CLIP_OUTSIDE_MASK: "+option.id+"/"+binding.path+"/"+binding.propertyName);
                Resolve(binding.path);var curve=AnimationUtility.GetEditorCurve(clip,binding);
                for(int sample=0;sample<=120;sample++)
                    if(!float.IsFinite(curve.Evaluate(clip.length*sample/120)))throw new Exception("PERFORMANCE_CURVE_INVALID: "+option.id);
            }
            }
        }
    }
}
