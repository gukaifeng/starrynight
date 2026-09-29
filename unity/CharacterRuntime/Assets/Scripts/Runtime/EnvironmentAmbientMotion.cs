using System;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class EnvironmentSway
    {
        public Transform target;
        public float degrees = 1.2f, frequency = .18f, phase;
        [NonSerialized] public Quaternion rest;
    }
    [Serializable] public sealed class EnvironmentCloth
    {
        public MeshFilter target;
        public float amplitude = .024f, phase;
        [NonSerialized] public Mesh mesh;
        [NonSerialized] public Vector3[] rest, vertices;
        [NonSerialized] public float[] weights;
    }

    /// Bounded local motion only: pinned curtain hems, rooted leaves and water UVs.
    /// There are no particles, physics, animated lights, camera changes or per-frame collections.
    public sealed class EnvironmentAmbientMotion : MonoBehaviour
    {
        public EnvironmentSway[] foliage = Array.Empty<EnvironmentSway>();
        public EnvironmentCloth[] curtains = Array.Empty<EnvironmentCloth>();
        public Renderer water;
        public Vector2 waterTiling = new Vector2(6, 10);
        public float waterSpeed = .008f;
        public int RendererCount { get; private set; }
        public int VertexCount { get; private set; }
        public int ActiveNodes => foliage.Length + curtains.Length + (water ? 1 : 0);
        public float Elapsed { get; private set; }
        public float PeakClothOffset { get; private set; }
        public float PeakSwayDegrees { get; private set; }
        public bool Suppressed => paused || unfocused;
        bool paused, unfocused;
        bool initialized;
        MaterialPropertyBlock waterBlock;
        static readonly int MapST = Shader.PropertyToID("_BaseMap_ST");
        static readonly int BumpScale = Shader.PropertyToID("_BumpScale");

        public void Initialize()
        {
            if (initialized) return;
            initialized = true;
            foreach (var item in foliage) if (item.target) item.rest = item.target.localRotation;
            foreach (var item in curtains)
            {
                if (!item.target || !item.target.sharedMesh) continue;
                item.mesh = Instantiate(item.target.sharedMesh);
                item.mesh.name = item.target.sharedMesh.name + " (local breeze)";
                item.mesh.MarkDynamic(); item.target.sharedMesh = item.mesh;
                item.rest = item.mesh.vertices; item.vertices = (Vector3[])item.rest.Clone();
                item.weights = new float[item.rest.Length];
                var bounds = item.mesh.bounds;
                for (int i = 0; i < item.rest.Length; i++)
                    item.weights[i] = Mathf.Pow(1 - Mathf.InverseLerp(bounds.min.y, bounds.max.y, item.rest[i].y), 1.65f);
                bounds.Expand(.12f); item.mesh.bounds = bounds;
            }
            if (water) waterBlock = new MaterialPropertyBlock();
            RendererCount = GetComponentsInChildren<Renderer>(true).Length;
            foreach (var filter in GetComponentsInChildren<MeshFilter>(true))
                if (filter.sharedMesh) VertexCount += filter.sharedMesh.vertexCount;
        }
        void OnEnable() { if (Application.isPlaying) Initialize(); }
        void OnApplicationPause(bool value) { paused = value; }
        void OnApplicationFocus(bool focused) { unfocused = !focused; }
        void Update() { Advance(Time.unscaledDeltaTime); }
        public void Advance(float deltaTime)
        {
            if (!initialized) Initialize();
            if(Suppressed || !gameObject.activeInHierarchy) return;
            Elapsed += Mathf.Clamp(deltaTime, 0, .05f);
            float time = Elapsed;
            PeakClothOffset = 0; PeakSwayDegrees = 0;
            foreach (var item in foliage)
            {
                if (!item.target || !item.target.gameObject.activeInHierarchy) continue;
                float wave = Mathf.Sin(time * item.frequency * Mathf.PI * 2 + item.phase);
                float slower = Mathf.Sin(time * item.frequency * 2.37f + item.phase * .7f);
                float x = item.degrees * (.72f * wave + .28f * slower);
                float z = item.degrees * .48f * Mathf.Sin(time * item.frequency * 4.1f + item.phase + 1);
                item.target.localRotation = item.rest * Quaternion.Euler(x, 0, z);
                PeakSwayDegrees = Mathf.Max(PeakSwayDegrees, Mathf.Max(Mathf.Abs(x), Mathf.Abs(z)));
            }
            foreach (var item in curtains)
            {
                if (!item.mesh || !item.target.gameObject.activeInHierarchy) continue;
                for (int i = 0; i < item.vertices.Length; i++)
                {
                    var rest = item.rest[i]; float weight = item.weights[i];
                    float drift = item.amplitude * weight * (.7f * Mathf.Sin(time * .71f + item.phase + rest.x * 2.1f)
                        + .3f * Mathf.Sin(time * 1.13f + item.phase + rest.y * 1.8f));
                    item.vertices[i] = rest + new Vector3(drift * .28f, 0, drift);
                    PeakClothOffset = Mathf.Max(PeakClothOffset, Mathf.Abs(drift));
                }
                // Small displacements retain the pleat normals; no normal rebuild/upload allocations.
                item.mesh.SetVertices(item.vertices);
            }
            if (water && water.gameObject.activeInHierarchy)
            {
                water.GetPropertyBlock(waterBlock);
                waterBlock.SetVector(MapST, new Vector4(waterTiling.x, waterTiling.y,
                    Mathf.Repeat(time * waterSpeed * .32f, 1), Mathf.Repeat(time * waterSpeed, 1)));
                waterBlock.SetFloat(BumpScale, .22f + .018f * Mathf.Sin(time * .38f));
                water.SetPropertyBlock(waterBlock);
            }
        }
        void OnDestroy()
        {
            foreach (var item in curtains) if (item.mesh) {
                if(Application.isPlaying) Destroy(item.mesh); else DestroyImmediate(item.mesh);
            }
        }
    }
}
