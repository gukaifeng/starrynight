using System;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ModelSpace
{
    [Serializable] public sealed class StudioSettings
    {
        public float faceWidth = .5f, jawShape = .5f, eyeSize = .5f, mouthShape = .5f, noseWidth = .5f;
        public float bodyBuild = .5f, bodyCurve = .5f, height = .5f;
        public string skin = "natural", eyes = "brown", hair = "long", hairColor = "espresso", clothing = "ivory", room = "sunroom";
        public EnvironmentSettings environment;
        public float lightAngle = -35, lightHeight = 48, lightIntensity = 1, shadow = .75f;
        public static float Safe(float value, float min, float max, float fallback)
            => float.IsNaN(value) || float.IsInfinity(value) ? fallback : Mathf.Clamp(value,min,max);
    }
    public sealed class CharacterStudioDriver : MonoBehaviour
    {
        public const int Revision = 2;
        public Transform[] rooms; // Legacy authoring adapter input only.
        public Light key, fill, rim;
        public Renderer oldGround;
        public EnvironmentDirector environment;
        RealCharacterAppearance appearance;
        public StudioSettings Current { get; private set; } = new StudioSettings();
        public void Bind(ViewerCharacter value)
        {
            appearance = value.GetComponent<RealCharacterAppearance>();
            if(environment) {
                environment.ToonPortrait=value.GetComponentsInChildren<Renderer>(true).Any(r=>r.sharedMaterials.Any(m=>m && m.shader.name=="Toon/Toon"));
                environment.Bind(value.RestBounds().size.y);
            }
        }
        public void Configure(StudioSettings value, bool immediate=false)
        {
            Current = value ?? new StudioSettings();
            if(environment) environment.Configure(Current,immediate);
            if(appearance) appearance.Configure(Current);
        }
    }
}
