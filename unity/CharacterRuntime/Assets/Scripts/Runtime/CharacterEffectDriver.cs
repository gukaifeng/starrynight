using UnityEngine;
namespace ModelSpace
{
    public sealed class CharacterEffectDriver : MonoBehaviour
    {
        ParticleSystem particles;
        ViewerCharacter character;
        Transform head;
        public void Bind(ViewerCharacter model)
        {
            Stop(); character=model; head=CharacterContract.Resolve(model.transform,model.Manifest.rig.head);
            if(particles) return;
            var go=new GameObject("CharacterEffects"); go.transform.SetParent(transform,false);
            particles=go.AddComponent<ParticleSystem>(); particles.Stop(true,ParticleSystemStopBehavior.StopEmittingAndClear);
            var main=particles.main; main.playOnAwake=false; main.loop=false; main.maxParticles=32;
            main.simulationSpace=ParticleSystemSimulationSpace.World; main.useUnscaledTime=true;
            var emission=particles.emission; emission.enabled=false;
            var shape=particles.shape; shape.enabled=false;
            var color=particles.colorOverLifetime; color.enabled=true;
            var gradient=new Gradient(); gradient.SetKeys(new[]{new GradientColorKey(Color.white,0),new GradientColorKey(Color.white,1)},
                new[]{new GradientAlphaKey(0,0),new GradientAlphaKey(1,.15f),new GradientAlphaKey(0,1)}); color.color=gradient;
            var size=particles.sizeOverLifetime; size.enabled=true; size.size=new ParticleSystem.MinMaxCurve(1,AnimationCurve.EaseInOut(0,.4f,1,1));
            var renderer=particles.GetComponent<ParticleSystemRenderer>(); renderer.shadowCastingMode=UnityEngine.Rendering.ShadowCastingMode.Off;
            renderer.receiveShadows=false;
        }
        public void Play(CharacterEffect effect,float intensity)
        {
            if(!particles || !character) return;
            var renderer=particles.GetComponent<ParticleSystemRenderer>();
            renderer.sharedMaterial=Resources.Load<Material>("CharacterPlatform/"+(effect.kind=="hearts"?"Heart":"Star"));
            if(!renderer.sharedMaterial) return;
            float scale=character.RestBounds().size.y;
            var origin=head ? head.position : character.transform.position+Vector3.up*scale*.8f;
            if(effect.anchor=="chest") origin-=Vector3.up*scale*.22f;
            ColorUtility.TryParseHtmlString(effect.color,out var color);
            particles.Play();
            for(int i=0;i<Mathf.Min(24,effect.count);i++)
            {
                var direction=Quaternion.Euler(0,i*137.5f,0)*Vector3.right;
                var emit=new ParticleSystem.EmitParams { position=origin+direction*scale*.12f,
                    velocity=(direction*.025f+Vector3.up*.09f)*scale, startLifetime=1.7f+(i%3)*.2f,
                    startSize=scale*.025f*Mathf.Lerp(.6f,1,Mathf.Clamp01(intensity)),startColor=color,rotation=i*27 };
                particles.Emit(emit,1);
            }
        }
        public void Stop() { if(particles) particles.Stop(true,ParticleSystemStopBehavior.StopEmittingAndClear); }
    }
}
