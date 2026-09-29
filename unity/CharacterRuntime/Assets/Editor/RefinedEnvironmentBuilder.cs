using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using ModelSpace;
using Object = UnityEngine.Object;

/// Project-authored, reproducible environment art. Curved surfaces, mapped materials,
/// layered distant scenery and small rooted motion replace the old placeholder blocks.
public static class RefinedEnvironmentBuilder
{
    const string Folder = "Assets/EnvironmentPackages/Refined";
    static readonly Dictionary<string, Material> Materials = new Dictionary<string, Material>();
    static readonly Dictionary<string, Mesh> Meshes = new Dictionary<string, Mesh>();
    static readonly Dictionary<string, Texture2D> Textures = new Dictionary<string, Texture2D>();
    sealed class Scene
    {
        public string id;
        public Transform root, structure, surface, decor, accent;
        public EnvironmentAmbientMotion motion;
        public List<EnvironmentSway> sways = new List<EnvironmentSway>();
        public List<EnvironmentCloth> cloth = new List<EnvironmentCloth>();
    }
    static Scene Begin(string id, Transform root = null)
    {
        Directory.CreateDirectory(Folder); AssetDatabase.Refresh();
        if (!root) root = new GameObject(id).transform;
        var scene = new Scene { id = id, root = root };
        scene.structure = Child(root, "Structural"); scene.surface = Child(root, "Surface");
        var decor = Child(root, "Decor"); scene.decor = Child(decor, "Fixed"); scene.accent = Child(decor, "Accent");
        scene.motion = root.gameObject.AddComponent<EnvironmentAmbientMotion>();
        return scene;
    }
    static Transform Child(Transform parent, string name)
    {
        var found = parent.Find(name); if (found) return found;
        var result = new GameObject(name).transform; result.SetParent(parent, false); return result;
    }
    static void Finish(Scene scene, bool combineStatic = true)
    {
        scene.motion.foliage = scene.sways.ToArray(); scene.motion.curtains = scene.cloth.ToArray();
        foreach (var item in scene.sways) Combine(item.target, scene.root.name + "_" + item.target.name);
        if(combineStatic) foreach (var group in new[] { scene.structure, scene.surface, scene.decor, scene.accent })
                Combine(group, scene.root.name + "_" + group.parent.name + "_" + group.name);
    }
    static bool DynamicAncestor(Transform item, Transform stop)
    {
        for (var t = item; t && t != stop; t = t.parent) if (t.name.StartsWith("Motion_", StringComparison.Ordinal)) return true;
        return false;
    }
    static void Combine(Transform root, string key)
    {
        var filters = root.GetComponentsInChildren<MeshFilter>(true)
            .Where(f => !DynamicAncestor(f.transform, root) && f.sharedMesh && f.GetComponent<MeshRenderer>() && f.transform.childCount == 0).ToArray();
        foreach (var group in filters.GroupBy(f => f.GetComponent<MeshRenderer>().sharedMaterial))
        {
            if (!group.Key) continue;
            var entries = group.ToArray(); if (entries.Length < 2) continue;
            var mesh = new Mesh { name = key + "_" + group.Key.name, indexFormat = IndexFormat.UInt32 };
            mesh.CombineMeshes(entries.Select(f => new CombineInstance { mesh = f.sharedMesh, transform = root.worldToLocalMatrix * f.transform.localToWorldMatrix }).ToArray());
            var saved = SaveMesh(mesh.name, mesh);
            foreach (var f in entries) Object.DestroyImmediate(f.gameObject);
            MeshObject(root, "Detail " + group.Key.name, saved, group.Key);
        }
    }
    static Material Mat(string name, Color color, float smooth = .25f, string pattern = null, bool unlit = false, float metal = 0)
    {
        if (Materials.TryGetValue(name, out var cached) && cached) return cached;
        string path = Folder + "/" + name + ".mat";
        var material = AssetDatabase.LoadAssetAtPath<Material>(path);
        var shader = Shader.Find(unlit ? "Universal Render Pipeline/Unlit" : "Universal Render Pipeline/Lit");
        if (!material) { material = new Material(shader); AssetDatabase.CreateAsset(material, path); } else material.shader = shader;
        material.SetColor("_BaseColor", color); material.SetFloat("_Smoothness", smooth); material.SetFloat("_Metallic", metal);
        material.SetFloat("_Cull", 0); material.enableInstancing = true;
        if (pattern != null)
        {
            material.SetTexture("_BaseMap", Texture(pattern));
            if (!unlit)
            {
                material.SetTexture("_BumpMap", Texture(pattern, true)); material.SetFloat("_BumpScale", pattern == "water" ? .22f : .14f);
                material.EnableKeyword("_NORMALMAP");
            }
        }
        EditorUtility.SetDirty(material); Materials[name] = material; return material;
    }
    static Texture2D Texture(string kind, bool normal = false)
    {
        string key = kind + (normal ? "_normal" : "_color");
        if (Textures.TryGetValue(key, out var cached) && cached) return cached;
        const int size = 256; var texture = new Texture2D(size, size, TextureFormat.RGBA32, true, normal);
        var pixels = new Color32[size * size];
        float Height(float u, float v)
        {
            float grain = Mathf.Sin(u * Mathf.PI * 2 * 32 + 1.8f * Mathf.Sin(v * Mathf.PI * 2 * 2) + .7f * Mathf.Sin(v * Mathf.PI * 2 * 7));
            float noise = Mathf.Sin(u * Mathf.PI * 2 * 73 + Mathf.Cos(v * Mathf.PI * 2 * 29)) * Mathf.Sin(v * Mathf.PI * 2 * 61);
            if (kind == "wood") return .5f + .16f * grain + .025f * noise;
            if (kind == "linen") return .5f + .08f * Mathf.Sin(u * Mathf.PI * 2 * 64) + .08f * Mathf.Sin(v * Mathf.PI * 2 * 64) + .025f * noise;
            if (kind == "water") return .5f + .18f * Mathf.Sin(v * Mathf.PI * 2 * 11 + .6f * Mathf.Sin(u * Mathf.PI * 2 * 3))
                + .08f * Mathf.Sin(v * Mathf.PI * 2 * 23 - u * Mathf.PI * 2 * 5);
            if (kind == "stone")
            {
                float edge = Mathf.Min(Mathf.Min(Mathf.Repeat(u, 1), 1 - Mathf.Repeat(u, 1)), Mathf.Min(Mathf.Repeat(v, 1), 1 - Mathf.Repeat(v, 1)));
                float joint = 1 - Mathf.SmoothStep(0, .0045f, edge);
                return .5f + .045f * noise + .028f * Mathf.Sin(u * Mathf.PI * 2 * 7) * Mathf.Cos(v * Mathf.PI * 2 * 11) - .32f * joint;
            }
            return .5f + .045f * noise + .035f * Mathf.Sin(u * Mathf.PI * 2 * 7) * Mathf.Cos(v * Mathf.PI * 2 * 11);
        }
        for (int y = 0; y < size; y++) for (int x = 0; x < size; x++)
        {
            float u = x / (float)size, v = y / (float)size, h = Height(u, v);
            if (normal)
            {
                var n = new Vector3((Height(u - 1f / size, v) - Height(u + 1f / size, v)) * .7f,
                    (Height(u, v - 1f / size) - Height(u, v + 1f / size)) * .7f, 1).normalized;
                pixels[y * size + x] = new Color(n.x * .5f + .5f, n.y * .5f + .5f, n.z * .5f + .5f, 1);
            }
            else
            {
                float value = kind == "wood" ? .82f + h * .24f : kind == "water" ? .72f + h * .4f : kind == "stone" ? .79f + h * .35f : .91f + h * .12f;
                pixels[y * size + x] = new Color(value, value, value, 1);
            }
        }
        texture.SetPixels32(pixels); texture.Apply();
        string path = Folder + "/" + key + ".png"; File.WriteAllBytes(path, texture.EncodeToPNG()); Object.DestroyImmediate(texture);
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceSynchronousImport);
        var importer = (TextureImporter)AssetImporter.GetAtPath(path); importer.textureType = normal ? TextureImporterType.NormalMap : TextureImporterType.Default;
        importer.mipmapEnabled = true; importer.wrapMode = TextureWrapMode.Repeat; importer.anisoLevel = 4; importer.maxTextureSize = 256;
        importer.SetPlatformTextureSettings(new TextureImporterPlatformSettings { name = "iPhone", overridden = true, maxTextureSize = 256, format = TextureImporterFormat.ASTC_6x6 });
        importer.SaveAndReimport(); return Textures[key] = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }
    static Texture2D DistantTexture(string art)
    {
        string path = "Assets/EnvironmentArt/" + art + ".png";
        if (!File.Exists(path)) return null;
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceSynchronousImport);
        var importer = (TextureImporter)AssetImporter.GetAtPath(path);
        importer.textureType = TextureImporterType.Default; importer.sRGBTexture = true; importer.mipmapEnabled = true;
        importer.wrapMode = TextureWrapMode.Clamp; importer.anisoLevel = 2; importer.maxTextureSize = 2048;
        // Keep the authored 3:2 dimensions; power-of-two resampling would stretch
        // the artwork before the aspect-preserving window crop is calculated.
        importer.npotScale = TextureImporterNPOTScale.None;
        importer.SetPlatformTextureSettings(new TextureImporterPlatformSettings { name = "iPhone", overridden = true, maxTextureSize = 2048, format = TextureImporterFormat.ASTC_6x6 });
        importer.SaveAndReimport(); return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }
    static Mesh SaveMesh(string key, Mesh mesh)
    {
        key = key.Replace('/', '_').Replace(' ', '_'); string path = Folder + "/" + key + ".asset";
        var saved = AssetDatabase.LoadAssetAtPath<Mesh>(path);
        if (saved) { EditorUtility.CopySerialized(mesh, saved); Object.DestroyImmediate(mesh); mesh = saved; } else AssetDatabase.CreateAsset(mesh, path);
        Meshes[key] = mesh; return mesh;
    }
    static GameObject MeshObject(Transform root, string name, Mesh mesh, Material mat, Vector3? position = null)
    {
        var go = new GameObject(name); go.transform.SetParent(root, false); go.transform.localPosition = position ?? Vector3.zero;
        go.AddComponent<MeshFilter>().sharedMesh = mesh; var renderer = go.AddComponent<MeshRenderer>(); renderer.sharedMaterial = mat;
        renderer.shadowCastingMode = ShadowCastingMode.On; renderer.receiveShadows = true; return go;
    }
    static GameObject Shape(Transform parent, string name, PrimitiveType type, Vector3 at, Vector3 scale, Material material)
    {
        var go = GameObject.CreatePrimitive(type); go.name = name; go.transform.SetParent(parent, false); go.transform.localPosition = at; go.transform.localScale = scale;
        Object.DestroyImmediate(go.GetComponent<Collider>()); go.GetComponent<Renderer>().sharedMaterial = material; return go;
    }
    static GameObject Box(Transform p, string n, Vector3 at, Vector3 size, Material mat, float bevel = .015f)
    {
        string key = string.Format(System.Globalization.CultureInfo.InvariantCulture, "Box_{0:F3}_{1:F3}_{2:F3}_{3:F3}", size.x, size.y, size.z, bevel);
        if (!Meshes.TryGetValue(key, out var mesh) || !mesh)
        {
            var vertices = new List<Vector3>(); var normals = new List<Vector3>(); var uv = new List<Vector2>(); var triangles = new List<int>();
            Vector3 half = size * .5f; float radius = Mathf.Min(bevel, Mathf.Min(half.x, Mathf.Min(half.y, half.z)) * .7f);
            var inner = half - Vector3.one * radius;
            for (int face = 0; face < 6; face++)
            {
                int axis = face / 2; float sign = face % 2 == 0 ? 1 : -1;
                Vector3 normal = axis == 0 ? Vector3.right * sign : axis == 1 ? Vector3.up * sign : Vector3.forward * sign;
                Vector3 a = axis == 0 ? Vector3.forward : Vector3.right, b = Vector3.Cross(normal, a);
                float ah = Vector3.Dot(half, new Vector3(Mathf.Abs(a.x), Mathf.Abs(a.y), Mathf.Abs(a.z)));
                float bh = Vector3.Dot(half, new Vector3(Mathf.Abs(b.x), Mathf.Abs(b.y), Mathf.Abs(b.z)));
                float nh = axis == 0 ? half.x : axis == 1 ? half.y : half.z;
                float[] us = { -ah, -ah + radius, 0, ah - radius, ah }, vs = { -bh, -bh + radius, 0, bh - radius, bh };
                int start = vertices.Count;
                for (int y = 0; y < 5; y++) for (int x = 0; x < 5; x++)
                {
                    Vector3 pnt = normal * nh + a * us[x] + b * vs[y];
                    Vector3 center = new Vector3(Mathf.Clamp(pnt.x, -inner.x, inner.x), Mathf.Clamp(pnt.y, -inner.y, inner.y), Mathf.Clamp(pnt.z, -inner.z, inner.z));
                    Vector3 edge = (pnt - center).normalized; vertices.Add(center + edge * radius); normals.Add(edge); uv.Add(new Vector2((us[x] + ah) * 2, (vs[y] + bh) * 2));
                    if (x < 4 && y < 4) { int i = start + y * 5 + x; triangles.AddRange(new[] { i, i + 1, i + 5, i + 1, i + 6, i + 5 }); }
                }
            }
            mesh = new Mesh { name = key }; mesh.SetVertices(vertices); mesh.SetNormals(normals); mesh.SetUVs(0, uv); mesh.SetTriangles(triangles, 0); mesh.RecalculateBounds(); mesh.RecalculateTangents(); mesh = SaveMesh(key, mesh);
        }
        return MeshObject(p, n, mesh, mat, at);
    }
    static GameObject Lathe(Transform p, string name, Vector3 at, Vector2[] profile, Material material, float pleat = 0)
    {
        const int segments = 48; string key = name + "_" + string.Join("_", profile.Select(v => v.x.ToString("F3", System.Globalization.CultureInfo.InvariantCulture) + "x" + v.y.ToString("F3", System.Globalization.CultureInfo.InvariantCulture)));
        if (!Meshes.TryGetValue(key, out var mesh) || !mesh)
        {
            var vertices = new List<Vector3>(); var uv = new List<Vector2>(); var triangles = new List<int>();
            for (int y = 0; y < profile.Length; y++) for (int x = 0; x <= segments; x++)
            {
                float u = x / (float)segments, theta = u * Mathf.PI * 2, r = profile[y].x + pleat * (.5f + .5f * Mathf.Cos(theta * 24));
                vertices.Add(new Vector3(Mathf.Cos(theta) * r, profile[y].y, Mathf.Sin(theta) * r)); uv.Add(new Vector2(u * 2, profile[y].y * 3));
                if (y < profile.Length - 1 && x < segments) { int k = y * (segments + 1) + x; triangles.AddRange(new[] { k, k + segments + 1, k + 1, k + 1, k + segments + 1, k + segments + 2 }); }
            }
            mesh = new Mesh { name = name }; mesh.SetVertices(vertices); mesh.SetUVs(0, uv); mesh.SetTriangles(triangles, 0); mesh.RecalculateNormals(); mesh.RecalculateBounds(); mesh.RecalculateTangents(); mesh = SaveMesh("Lathe_" + key, mesh);
        }
        return MeshObject(p, name, mesh, material, at);
    }
    static void Backdrop(Scene scene, string art, Vector3 at, Vector2 size, bool night)
    {
        string aspectKey = (size.x / size.y).ToString("F3", System.Globalization.CultureInfo.InvariantCulture);
        var mat = Mat("Scenery_" + art + "_" + scene.id + "_" + aspectKey, Color.white, .1f, null, true); var image = DistantTexture(art);
        if (image)
        {
            // Cover the reveal without stretching: crop the longer image axis around its centre.
            float imageAspect = image.width / (float)image.height, planeAspect = size.x / size.y;
            Vector2 crop = planeAspect < imageAspect ? new Vector2(planeAspect / imageAspect, 1) : new Vector2(1, imageAspect / planeAspect);
            mat.SetTexture("_BaseMap", image); mat.SetTextureScale("_BaseMap", crop); mat.SetTextureOffset("_BaseMap", (Vector2.one - crop) * .5f);
        }
        else mat.SetColor("_BaseColor", night ? new Color(.06f, .12f, .23f) : new Color(.43f, .62f, .68f));
        EditorUtility.SetDirty(mat);
        var panel = Shape(scene.structure, "Distant scenery " + art, PrimitiveType.Quad, at, new Vector3(size.x, size.y, 1), mat);
        var renderer = panel.GetComponent<Renderer>(); renderer.shadowCastingMode = ShadowCastingMode.Off; renderer.receiveShadows = false;
    }
    static void WoodFloor(Scene scene, bool deck = false)
    {
        var wood = Mat(deck ? "WeatheredTeak" : "SmokedOak", deck ? new Color(.37f, .34f, .29f) : new Color(.43f, .34f, .27f), .3f, "wood");
        // The long floor remains a true receiving surface. Fine seams are geometric, then batched.
        for (int i = 0; i < 30; i++) Box(deck ? scene.surface : scene.structure, "Floor board", new Vector3((i - 14.5f) * .32f, -.029f, deck ? 5.5f : 5), new Vector3(.315f, .058f, deck ? 17 : 24), wood, .004f);
    }
    static void Curtain(Scene scene, Vector3 top, float width, float height, Material material, float phase)
    {
        const int columns = 32, rows = 14; var vertices = new List<Vector3>(); var uv = new List<Vector2>(); var triangles = new List<int>();
        for (int y = 0; y <= rows; y++) for (int x = 0; x <= columns; x++)
        {
            float u = x / (float)columns, v = y / (float)rows;
            float fullness = 1 + .12f * v * v;
            vertices.Add(new Vector3((u - .5f) * width * fullness, -v * height, Mathf.Sin(u * Mathf.PI * 18) * .035f * (.85f + .15f * v)));
            uv.Add(new Vector2(u * 3, v * 5));
            if (x < columns && y < rows) { int k = y * (columns + 1) + x; triangles.AddRange(new[] { k, k + columns + 1, k + 1, k + 1, k + columns + 1, k + columns + 2 }); }
        }
        var mesh = new Mesh { name = "Pinned woven curtain" }; mesh.SetVertices(vertices); mesh.SetUVs(0, uv); mesh.SetTriangles(triangles, 0); mesh.RecalculateNormals(); mesh.RecalculateTangents(); mesh.RecalculateBounds();
        mesh = SaveMesh(scene.root.name + "_curtain_" + scene.cloth.Count, mesh);
        var go = MeshObject(scene.structure, "Motion_Pinned curtain " + scene.cloth.Count, mesh, material, top);
        scene.cloth.Add(new EnvironmentCloth { target = go.GetComponent<MeshFilter>(), amplitude = .024f, phase = phase });
    }
    static Mesh LeafMesh()
    {
        const string key = "BotanicalCurvedLeaf"; if (Meshes.TryGetValue(key, out var cached) && cached) return cached;
        var vertices = new List<Vector3>(); var uv = new List<Vector2>(); var triangles = new List<int>();
        for (int row = 0; row <= 8; row++)
        {
            float t = row / 8f, width = Mathf.Pow(Mathf.Max(.008f, Mathf.Sin(t * Mathf.PI)), .8f) * .19f;
            for (int col = 0; col < 3; col++) { float x = (col - 1) * width; vertices.Add(new Vector3(x, t, Mathf.Sin(t * Mathf.PI) * .11f + (col == 1 ? .025f : 0) - t * t * .30f)); uv.Add(new Vector2(col * .5f, t)); }
            if (row < 8) for (int col = 0; col < 2; col++) { int k = row * 3 + col; triangles.AddRange(new[] { k, k + 1, k + 3, k + 1, k + 4, k + 3 }); }
        }
        var mesh = new Mesh { name = key }; mesh.SetVertices(vertices); mesh.SetUVs(0, uv); mesh.SetTriangles(triangles, 0); mesh.RecalculateNormals(); mesh.RecalculateTangents(); mesh.RecalculateBounds(); return SaveMesh(key, mesh);
    }
    static void Plant(Scene scene, Vector3 at, float size, int seed, bool pot = true, bool flowers = false)
    {
        var ceramic = Mat("MatteCeramic", new Color(.47f, .46f, .41f), .3f, "plaster");
        var leaf = Mat("BotanicalJade", new Color(.13f, .26f, .19f), .26f, "linen");
        var young = Mat("BotanicalSage", new Color(.27f, .40f, .28f), .23f, "linen");
        var stem = Mat("BotanicalStems", new Color(.25f, .31f, .19f), .2f);
        float bottom = pot ? .36f * size : 0;
        if (pot)
        {
            Lathe(scene.decor, "Handthrown planter", at, new[] { new Vector2(.16f * size, 0), new Vector2(.20f * size, .04f * size), new Vector2(.23f * size, .30f * size), new Vector2(.225f * size, .36f * size), new Vector2(.19f * size, .36f * size), new Vector2(.18f * size, .32f * size) }, ceramic);
            Shape(scene.decor, "Pot soil", PrimitiveType.Cylinder, at + Vector3.up * (.328f * size), new Vector3(.38f * size, .008f, .38f * size), Mat("PottingEarth", new Color(.10f, .085f, .07f), .1f, "plaster"));
        }
        var cluster = Child(scene.decor, "Motion_Botanical_" + seed); cluster.localPosition = at + Vector3.up * bottom;
        int count = flowers ? 12 : 17;
        for (int i = 0; i < count; i++)
        {
            float angle = i * 137.508f + seed * 19, radians = angle * Mathf.Deg2Rad, height = (.39f + (i % 5) * .085f) * size;
            var baseAt = new Vector3(Mathf.Sin(radians) * .055f * size, (i % 3) * .025f * size, Mathf.Cos(radians) * .055f * size);
            var blade = MeshObject(cluster, "Veined pointed leaf", LeafMesh(), i % 4 == 0 ? young : leaf, baseAt);
            blade.transform.localRotation = Quaternion.Euler(28 + (i % 5) * 7, angle, 0); blade.transform.localScale = new Vector3(size * .8f, height, size);
            if (flowers && i % 3 == 0)
            {
                var budAt = baseAt + new Vector3(Mathf.Sin(radians) * .12f, .42f * size, Mathf.Cos(radians) * .12f);
                Shape(cluster, "Fine flower stem", PrimitiveType.Cylinder, budAt * .5f, new Vector3(.008f, budAt.y * .5f, .008f), stem);
                var petals = Mat("MutedRosePetals", new Color(.66f, .45f, .46f), .18f, "linen");
                for (int petal = 0; petal < 5; petal++)
                {
                    float a = petal * Mathf.PI * .4f;
                    var flower = Shape(cluster, "Petal", PrimitiveType.Sphere, budAt + new Vector3(Mathf.Cos(a) * .037f, 0, Mathf.Sin(a) * .037f), new Vector3(.068f, .025f, .055f), petals);
                    flower.transform.localRotation = Quaternion.Euler(0, -a * Mathf.Rad2Deg, 12);
                }
            }
        }
        scene.sways.Add(new EnvironmentSway { target = cluster, degrees = pot ? 1.05f : 1.35f, frequency = .11f + seed % 5 * .014f, phase = seed * 1.71f });
    }
    static void Bench(Scene scene, Vector3 at, float width = 1.65f)
    {
        var wood = Mat("WalnutFurniture", new Color(.30f, .22f, .17f), .3f, "wood");
        var fabric = Mat("OatmealUpholstery", new Color(.66f, .63f, .55f), .18f, "linen");
        Box(scene.decor, "Rounded bench frame", at + new Vector3(0, .40f, 0), new Vector3(width, .12f, .64f), wood, .035f);
        Box(scene.decor, "Soft seat", at + new Vector3(0, .51f, 0), new Vector3(width - .08f, .17f, .60f), fabric, .08f);
        Box(scene.decor, "Soft back", at + new Vector3(0, .79f, -.27f), new Vector3(width - .06f, .50f, .13f), fabric, .06f);
        foreach (float side in new[] { -1f, 1f }) Box(scene.decor, "Tapered furniture leg", at + new Vector3(side * (width * .5f - .14f), .18f, 0), new Vector3(.065f, .36f, .47f), wood, .018f);
        var cushion = Box(scene.accent, "Tailored cushion", at + new Vector3(-width * .25f, .77f, -.10f), new Vector3(.38f, .38f, .16f), Mat("CushionFabric", new Color(.48f, .57f, .53f), .18f, "linen"), .075f);
        cushion.transform.localRotation = Quaternion.Euler(-12, 9, -8);
    }
    static void Lamp(Scene scene, Vector3 at)
    {
        var brass = Mat("BrushedBrass", new Color(.47f, .35f, .20f), .52f, "plaster", false, .7f);
        Shape(scene.decor, "Weighted lamp base", PrimitiveType.Cylinder, at + Vector3.up * .026f, new Vector3(.39f, .026f, .39f), brass);
        Shape(scene.decor, "Fine lamp stem", PrimitiveType.Cylinder, at + Vector3.up * .77f, new Vector3(.024f, .75f, .024f), brass);
        var shade = Mat("WarmSilkShade", new Color(.93f, .72f, .44f), .15f, "linen");
        shade.EnableKeyword("_EMISSION"); shade.SetColor("_EmissionColor", new Color(.23f, .14f, .055f)); EditorUtility.SetDirty(shade);
        Lathe(scene.decor, "Pleated linen lampshade", at + Vector3.up * 1.40f, new[] { new Vector2(.28f, 0), new Vector2(.278f, .02f), new Vector2(.19f, .40f), new Vector2(.185f, .42f) }, shade, .004f);
        Lathe(scene.decor, "Shade brass rim", at + Vector3.up * 1.40f, new[] { new Vector2(.282f, 0), new Vector2(.282f, .011f) }, brass);
    }
    public static Transform CreateRoom(string id)
    {
        var s = Begin(id); bool night = id == "evening", studio = id == "studio";
        var plaster = Mat(id + "Limewash", night ? new Color(.20f, .25f, .28f) : studio ? new Color(.37f, .44f, .44f) : new Color(.69f, .65f, .55f), .18f, "plaster");
        var trim = Mat("WarmIvoryTrim", new Color(.68f, .66f, .59f), .25f, "plaster");
        var wood = Mat("WalnutFurniture", new Color(.30f, .22f, .17f), .3f, "wood");
        WoodFloor(s);
        Box(s.surface, "Limewashed back wall", new Vector3(0, 2.45f, -3.65f), new Vector3(13, 4.9f, .16f), plaster, .008f);
        Box(s.structure, "Low skirting", new Vector3(0, .10f, -3.52f), new Vector3(13, .19f, .06f), trim, .012f);
        // Large glazing and layered reveal keep a visible detailed scene even in close portrait framing.
        float windowX = studio ? 2.1f : -1.55f, windowWidth = studio ? 1.8f : 3.05f;
        Backdrop(s, night ? "NightGarden" : "MorningGarden", new Vector3(windowX, 2.18f, -3.545f), new Vector2(windowWidth, 2.90f), night);
        foreach (float side in new[] { -1f, 1f })
        {
            Box(s.structure, "Deep window jamb", new Vector3(windowX + side * (windowWidth * .5f + .045f), 2.18f, -3.42f), new Vector3(.09f, 3.08f, .22f), wood, .008f);
            Curtain(s, new Vector3(windowX + side * (windowWidth * .5f + .12f), 3.76f, -3.18f), studio ? .32f : .52f, 3.50f,
                Mat(night ? "NightWovenCurtain" : "PearlWovenCurtain", night ? new Color(.52f, .56f, .60f) : new Color(.80f, .77f, .67f), .18f, "linen"), side + 2);
        }
        foreach (float y in new[] { .68f, 3.70f }) Box(s.structure, "Window reveal", new Vector3(windowX, y, -3.42f), new Vector3(windowWidth + .18f, .09f, .22f), wood, .008f);
        Box(s.structure, "Window slender mullion", new Vector3(windowX, 2.18f, -3.36f), new Vector3(.035f, 2.96f, .10f), trim, .004f);
        Box(s.structure, "Stone window sill", new Vector3(windowX, .66f, -3.32f), new Vector3(windowWidth + .28f, .07f, .40f), trim, .012f);
        // Timber slats add tactile rhythm instead of a featureless studio backdrop.
        float slatX = studio ? -2.25f : 1.55f;
        for (int i = 0; i < 14; i++) Box(s.structure, "Fine wall rib", new Vector3(slatX + (i - 6.5f) * .12f, 1.40f, -3.49f), new Vector3(.035f, 2.36f, .034f), wood, .005f);
        Box(s.decor, "Floating oak shelf", new Vector3(slatX, 1.23f, -3.25f), new Vector3(2.05f, .07f, .48f), wood, .02f);
        for (int i = 0; i < 6; i++)
        {
            float height = .27f + i % 3 * .045f;
            var cover = Mat("QuietBook" + i, Color.Lerp(new Color(.30f, .41f, .38f), new Color(.55f, .41f, .32f), i / 5f), .2f, "linen");
            Box(s.decor, "Clothbound volume", new Vector3(slatX - .71f + i * .105f, 1.285f + height * .5f, -3.22f), new Vector3(.079f, height, .22f), cover, .005f);
            Box(s.decor, "Book spine foil", new Vector3(slatX - .71f + i * .105f, 1.35f, -3.104f), new Vector3(.048f, .008f, .003f), trim, .001f);
        }
        Lathe(s.decor, "Sculpted ceramic vase", new Vector3(slatX + .53f, 1.265f, -3.23f), new[] { new Vector2(.07f, 0), new Vector2(.13f, .08f), new Vector2(.14f, .21f), new Vector2(.055f, .31f), new Vector2(.055f, .35f) }, Mat("PorcelainVase", new Color(.61f, .65f, .62f), .43f, "plaster"));
        Plant(s, new Vector3(studio ? -2.55f : -2.65f, 0, -1.65f), 1.1f, 2);
        Plant(s, new Vector3(studio ? 2.75f : 2.60f, 0, -2.65f), .72f, 7);
        Bench(s, new Vector3(studio ? -2.10f : 2.04f, 0, -2.0f), studio ? 1.1f : 1.75f);
        if (night || studio) Lamp(s, new Vector3(studio ? -3.15f : 3.15f, 0, -2.7f));
        Finish(s); return s.root;
    }
    public static Transform CreateOutdoor(string id)
    {
        var s = Begin(id); bool sea = id == "seaside";
        var stone = Mat("QuietLimestone", new Color(.55f, .58f, .54f), .22f, "plaster");
        var wood = Mat("WeatheredTeak", new Color(.37f, .34f, .29f), .3f, "wood");
        Backdrop(s, sea ? "BlueHourCoast" : "MorningGarden", new Vector3(0, 4.3f, -13), new Vector2(37, 10), sea);
        if (sea)
        {
            WoodFloor(s, true);
            var seaMaterial = Mat("LayeredCoastalWater", new Color(.16f, .31f, .37f), .72f, "water");
            var water = Shape(s.structure, "Motion_Water surface", PrimitiveType.Cube, new Vector3(0, -.17f, -15), new Vector3(46, .08f, 28), seaMaterial);
            s.motion.water = water.GetComponent<Renderer>(); s.motion.water.shadowCastingMode = ShadowCastingMode.Off;
            s.motion.waterTiling = new Vector2(6, 10); seaMaterial.SetTextureScale("_BaseMap", s.motion.waterTiling);
            var rail = Mat("CoastalRail", new Color(.50f, .55f, .55f), .40f, "plaster", false, .45f);
            for (int i = 0; i < 10; i++) Box(s.structure, "Slender baluster", new Vector3(-4.3f + i * .96f, .47f, -3.28f), new Vector3(.04f, .94f, .045f), rail, .006f);
            Box(s.structure, "Rounded timber handrail", new Vector3(0, .97f, -3.28f), new Vector3(9, .075f, .10f), wood, .025f);
            for (int i = 0; i < 3; i++) Box(s.structure, "Fine horizontal cable", new Vector3(0, .23f + i * .22f, -3.28f), new Vector3(9, .006f, .006f), rail, .001f);
            Bench(s, new Vector3(2.5f, 0, -1.75f)); Plant(s, new Vector3(-2.4f, 0, -1.6f), 1.15f, 31);
            Plant(s, new Vector3(3.3f, 0, -2.85f), .9f, 32);
            Lamp(s, new Vector3(-3.25f, 0, -2.55f));
        }
        else
        {
            Box(s.structure, "Continuous garden ground", new Vector3(0, -.05f, 0), new Vector3(38, .10f, 38), Mat("GardenSoilMoss", new Color(.24f, .31f, .23f), .12f, "plaster"), .003f);
            Box(s.surface, "Stone conversation terrace", new Vector3(0, -.014f, 0), new Vector3(4.6f, .028f, 5), stone, .008f);
            for (int i = 0; i < 7; i++) Box(s.structure, "Weathered stepping stone", new Vector3((i % 2) * .11f, .006f, -3.2f - i * .68f), new Vector3(.95f, .045f, .48f), stone, .035f);
            for (int i = 0; i < 10; i++)
            {
                float side = i % 2 == 0 ? -1 : 1; float x = side * (2.55f + i % 3 * .28f), z = -.7f - i / 2 * 1.07f;
                Plant(s, new Vector3(x, 0, z), .8f + (i % 3) * .18f, 50 + i, false, i % 3 == 0);
            }
            Bench(s, new Vector3(2.9f, 0, -2.0f));
            // Open pergola: stationary shadow geometry, no opaque spherical tree crowns.
            foreach (float x in new[] { -3.65f, 3.65f }) Box(s.structure, "Pergola post", new Vector3(x, 1.76f, -3.65f), new Vector3(.12f, 3.52f, .12f), wood, .012f);
            Box(s.structure, "Pergola beam", new Vector3(0, 3.5f, -3.65f), new Vector3(7.65f, .14f, .22f), wood, .012f);
            for (int i = 0; i < 12; i++) Box(s.structure, "Pergola roof batten", new Vector3((i - 5.5f) * .65f, 3.61f, -3.7f), new Vector3(.07f, .10f, 1.4f), wood, .008f);
        }
        Finish(s); return s.root;
    }
    public static void RefineCourtyard(Transform root, EnvironmentManifest manifest)
    {
        // The shipped CC0 courtyard is an intentionally tiny interoperability sample.
        // Retain its imported floor/architecture; add application-owned decorative art.
        var decor = root.Find("Decor");
        if (decor) foreach (Transform item in decor.Cast<Transform>().ToArray()) Object.DestroyImmediate(item.gameObject);
        var s = Begin("courtyard", root);
        var stone = Mat("CourtyardCutStone", new Color(.58f, .61f, .53f), .23f, "stone");
        var floor = root.Find("Floor");
        if (floor)
        {
            MapCourtyardFloorUV(floor, root);
            foreach (var renderer in floor.GetComponentsInChildren<Renderer>()) renderer.sharedMaterial = stone;
            floor.SetParent(s.structure, true);
        }
        foreach (var renderer in s.surface.GetComponentsInChildren<Renderer>(true)) renderer.sharedMaterial = Mat("CourtyardLimewash", new Color(.62f, .67f, .57f), .18f, "plaster");
        Backdrop(s, "MorningGarden", new Vector3(0, 4.3f, -11), new Vector2(28, 10), false);
        // A low planted boundary gives the distant image a real, irregular foreground
        // instead of meeting a featureless floor in one straight line behind the portrait.
        var border = Child(s.structure, "Distant planted border");
        var borderStone = Mat("CourtyardBorderLimestone", new Color(.43f, .48f, .42f), .21f, "stone");
        for (int i = 0; i < 11; i++)
            Box(border, "Low cut-stone edging", new Vector3(i - 5, .13f, -9.35f), new Vector3(.992f, .26f, .46f), borderStone, .028f);
        Combine(border, "Courtyard_DistantPlantedBorder");
        for (int i = 0; i < 9; i++)
        {
            Plant(s, new Vector3((i - 4) * 1.2f + Mathf.Sin(i * 2.1f) * .10f, .13f, -9.50f + Mathf.Sin(i * 1.7f) * .16f),
                .86f + (i % 3) * .09f, 180 + i, false);
            // This is the permanent landscape boundary; the decoration switch still
            // controls optional near furniture and pots without reopening the seam.
            s.sways[s.sways.Count - 1].target.SetParent(s.structure, true);
        }
        var timber = Mat("CourtyardCedar", new Color(.37f, .30f, .22f), .26f, "wood");
        for (int i = 0; i < 17; i++) Box(s.structure, "Courtyard timber lattice", new Vector3((i - 8) * .4f, 2.92f, -3.34f), new Vector3(.045f, .55f, .07f), timber, .005f);
        for (int i = 0; i < 3; i++) Box(s.structure, "Courtyard lattice rail", new Vector3(0, 2.67f + i * .25f, -3.34f), new Vector3(6.8f, .027f, .065f), timber, .004f);
        Bench(s, new Vector3(2.7f, 0, -.25f), 1.55f);
        Plant(s, new Vector3(-2.85f, 0, -2.75f), 1.18f, 71);
        Plant(s, new Vector3(2.85f, 0, -2.75f), .94f, 72, true, true);
        Plant(s, new Vector3(-3.7f, 0, -.50f), 1.1f, 73);
        var curtainMat = Mat("CourtyardCanvas", new Color(.72f, .72f, .63f), .16f, "linen");
        Curtain(s, new Vector3(-3.08f, 3.12f, -3.20f), .35f, 2.84f, curtainMat, 3);
        Curtain(s, new Vector3(3.08f, 3.12f, -3.20f), .35f, 2.84f, curtainMat, 5);
        manifest.bindings.surface = new[] { "Surface" }; manifest.bindings.accent = new[] { "Decor/Accent" }; manifest.bindings.decor = new[] { "Decor" };
        // XEP clearance is deliberately conservative and checks each renderer AABB.
        // Keep opposite walls/planters separate, so their union never fills the clear actor zone.
        Finish(s, false);
    }
    static void MapCourtyardFloorUV(Transform floor, Transform environment)
    {
        var filter = floor.GetComponent<MeshFilter>();
        if (!filter || !filter.sharedMesh || !filter.sharedMesh.isReadable) throw new Exception("COURTYARD_FLOOR_MESH_UNREADABLE");
        // The source GLB intentionally shares its UV-less box geometry with other
        // architecture. Clone it so adding floor UVs never mutates walls or the source asset.
        var mesh = Object.Instantiate(filter.sharedMesh); mesh.name = "Courtyard floor with metre-scaled stone UV";
        var vertices = mesh.vertices; var normals = mesh.normals; var uv = new Vector2[vertices.Length];
        if(normals.Length != vertices.Length) throw new Exception("COURTYARD_FLOOR_NORMALS_MISSING");
        Vector2 min = Vector2.positiveInfinity, max = Vector2.negativeInfinity; int topVertices = 0;
        for (int i = 0; i < vertices.Length; i++)
        {
            Vector3 p = environment.InverseTransformPoint(floor.TransformPoint(vertices[i]));
            Vector3 n = i < normals.Length ? normals[i] : Vector3.up;
            uv[i] = Mathf.Abs(n.y) > .5f ? new Vector2(p.x, p.z) * .55f
                : Mathf.Abs(n.x) > .5f ? new Vector2(p.z, p.y) * .55f : new Vector2(p.x, p.y) * .55f;
            if (n.y > .5f) { min = Vector2.Min(min, uv[i]); max = Vector2.Max(max, uv[i]); topVertices++; }
        }
        mesh.uv = uv; mesh.RecalculateTangents();
        var triangles = mesh.triangles; float topArea = 0;
        for (int i = 0; i + 2 < triangles.Length; i += 3)
        {
            int a = triangles[i], b = triangles[i + 1], c = triangles[i + 2];
            if (normals[a].y <= .5f || normals[b].y <= .5f || normals[c].y <= .5f) continue;
            Vector2 ab = uv[b] - uv[a], ac = uv[c] - uv[a]; topArea += Mathf.Abs(ab.x * ac.y - ab.y * ac.x) * .5f;
        }
        Vector2 span = max - min;
        if (mesh.uv.Length != mesh.vertexCount || topVertices < 4 || span.x < 15 || span.y < 15 || span.x > 30 || span.y > 30 || topArea < 200)
            throw new Exception("COURTYARD_FLOOR_UV_INVALID: vertices=" + topVertices + " span=" + span + " area=" + topArea);
        filter.sharedMesh = SaveMesh("Courtyard_FloorWorldUV", mesh);
    }
}
