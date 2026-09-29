using System;
using System.Collections.Generic;
using UnityEngine;
namespace ModelSpace
{
    // Own only explicitly mapped expression channels. Restore the animation baseline before
    // the next sample; appearance and speech channels are validated as disjoint at import.
    [DefaultExecutionOrder(55)]
    public sealed class CharacterExpressionDriver : MonoBehaviour
    {
        sealed class Slot { public SkinnedMeshRenderer skin; public int index; public float baseline,value,target,scale; }
        readonly List<Slot> slots=new List<Slot>();
        readonly Dictionary<string,List<(Slot slot,float weight)>> expressions=new Dictionary<string,List<(Slot,float)>>();
        bool applied;
        public void Bind(ViewerCharacter character)
        {
            Restore(); slots.Clear(); expressions.Clear();
            foreach(var expression in character.Manifest.expressions)
            {
                var targets=new List<(Slot,float)>();
                foreach(var binding in expression.bindings)
                {
                    var skin=CharacterContract.Resolve(character.transform,binding.renderer)?.GetComponent<SkinnedMeshRenderer>();
                    int index=skin ? skin.sharedMesh.GetBlendShapeIndex(binding.shape) : -1;
                    if(index<0) throw new ArgumentException("CHARACTER_EXPRESSION_BINDING: "+expression.id);
                    var slot=slots.Find(s=>s.skin==skin && s.index==index);
                    if(slot==null) { slot=new Slot { skin=skin,index=index,scale=CharacterContract.MorphScale(skin,index) }; slots.Add(slot); }
                    targets.Add((slot,binding.weight));
                }
                expressions[expression.id]=targets;
            }
        }
        public void Set(string id,float intensity)
        {
            foreach(var slot in slots) slot.target=0;
            if(expressions.TryGetValue(id,out var targets))
                foreach(var target in targets) target.slot.target=Mathf.Clamp01(target.weight*intensity)*target.slot.scale;
        }
        void Restore() { if(!applied) return; foreach(var slot in slots) if(slot.skin) slot.skin.SetBlendShapeWeight(slot.index,slot.baseline); applied=false; }
        void Update() { Restore(); }
        void OnDisable() { Restore(); }
        void LateUpdate()
        {
            foreach(var slot in slots)
            {
                slot.baseline=slot.skin.GetBlendShapeWeight(slot.index);
                slot.value=Mathf.Lerp(slot.value,slot.target,1-Mathf.Exp(-9*Time.unscaledDeltaTime));
                slot.skin.SetBlendShapeWeight(slot.index,Mathf.Clamp(slot.baseline+slot.value,0,slot.scale));
            }
            applied=true;
        }
    }
}
