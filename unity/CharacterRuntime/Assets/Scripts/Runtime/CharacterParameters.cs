using System;
using UnityEngine;
namespace ModelSpace
{
    [DefaultExecutionOrder(40)]
    public sealed class CharacterParameters : MonoBehaviour
    {
        sealed class Binding
        {
            public Transform transform;
            public SkinnedMeshRenderer skin;
            public Renderer renderer;
            public int positive=-1,negative=-1,property,materialSlot;
            public float positiveScale,negativeScale;
            public Color color;
            public bool toon;
            public Color firstShadeRatio,secondShadeRatio;
        }
        sealed class Slot { public CharacterParameter spec; public float current,target; public Binding[] bindings; public Color[] colors; }
        Slot[] slots=Array.Empty<Slot>();
        MaterialPropertyBlock block;
        public void Bind(ViewerCharacter model)
        {
            block=new MaterialPropertyBlock();
            slots=Array.ConvertAll(model.Manifest.parameters,p=> {
                var slot=new Slot { spec=p,current=p.initial,target=p.initial,colors=Array.ConvertAll(p.options,c=> { ColorUtility.TryParseHtmlString(c,out var color); return color; }) };
                slot.bindings=Array.ConvertAll(p.bindings,b=> {
                    var t=CharacterContract.Resolve(model.transform,b.path);
                    var binding=new Binding { transform=t,skin=t.GetComponent<SkinnedMeshRenderer>(),renderer=t.GetComponent<Renderer>(),materialSlot=b.materialSlot };
                    if(p.kind=="morph")
                    {
                        binding.positive=binding.skin.sharedMesh.GetBlendShapeIndex(b.property);
                        binding.negative=string.IsNullOrEmpty(b.negativeShape)?-1:binding.skin.sharedMesh.GetBlendShapeIndex(b.negativeShape);
                        binding.positiveScale=CharacterContract.MorphScale(binding.skin,binding.positive);
                        binding.negativeScale=binding.negative<0?0:CharacterContract.MorphScale(binding.skin,binding.negative);
                    }
                    if(p.kind=="color")
                    {
                        var material=binding.renderer.sharedMaterials[b.materialSlot];
                        binding.property=Shader.PropertyToID(CharacterContract.ColorProperty(material,b.property));
                        binding.toon=material.shader.name=="Toon/Toon" && binding.property==Shader.PropertyToID("_BaseColor");
                        if(binding.toon)
                        {
                            var original=material.GetColor("_BaseColor");
                            Color Ratio(Color shade)=>new Color(shade.r/Mathf.Max(.001f,original.r),shade.g/Mathf.Max(.001f,original.g),shade.b/Mathf.Max(.001f,original.b),1);
                            binding.firstShadeRatio=Ratio(material.GetColor("_1st_ShadeColor"));binding.secondShadeRatio=Ratio(material.GetColor("_2nd_ShadeColor"));
                        }
                        binding.renderer.GetPropertyBlock(block,b.materialSlot);
                        binding.color=block.HasColor(binding.property)?block.GetColor(binding.property):material.GetColor(binding.property);block.Clear();
                    }
                    return binding;
                }); return slot;
            });
            foreach(var slot in slots) Apply(slot,1);
        }
        public void Configure(CharacterParameterValue[] values)
        {
            foreach(var slot in slots) slot.target=slot.spec.initial;
            foreach(var value in values ?? Array.Empty<CharacterParameterValue>())
            {
                var slot=Array.Find(slots,s=>s.spec.id==value.id);
                if(slot!=null && !float.IsNaN(value.value) && !float.IsInfinity(value.value)) slot.target=Mathf.Clamp(value.value,slot.spec.min,slot.spec.max);
            }
        }
        public void ApplyImmediately()
        {
            foreach(var slot in slots) { slot.current=slot.target; Apply(slot,1); }
        }
        void LateUpdate()
        {
            float alpha=1-Mathf.Exp(-10*Time.unscaledDeltaTime);
            foreach(var slot in slots) { slot.current=Mathf.Lerp(slot.current,slot.target,alpha); Apply(slot,alpha); }
        }
        void Apply(Slot slot,float alpha)
        {
            int option=Mathf.Clamp(Mathf.RoundToInt(slot.target),0,slot.spec.options.Length-1);
            for(int i=0;i<slot.bindings.Length;i++)
            {
                var b=slot.bindings[i];
                switch(slot.spec.kind)
                {
                    case "variant": if(b.transform.gameObject.activeSelf!=(i==option)) b.transform.gameObject.SetActive(i==option); break;
                    case "morph":
                        float value=b.negative>=0 ? (slot.current-.5f)*2 : slot.current;
                        b.skin.SetBlendShapeWeight(b.positive,Mathf.Max(0,value)*b.positiveScale);
                        if(b.negative>=0) b.skin.SetBlendShapeWeight(b.negative,Mathf.Max(0,-value)*b.negativeScale);break;
                    case "color":
                        b.color=Color.Lerp(b.color,slot.colors[option],alpha);
                        b.renderer.GetPropertyBlock(block,b.materialSlot);block.SetColor(b.property,b.color);
                        if(b.toon) {block.SetColor("_1st_ShadeColor",b.color*b.firstShadeRatio);block.SetColor("_2nd_ShadeColor",b.color*b.secondShadeRatio);}
                        b.renderer.SetPropertyBlock(block,b.materialSlot);block.Clear();break;
                }
            }
        }
    }
}
