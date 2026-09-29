using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;

/// Geometry/motion audit deliberately performs no GPU render requests.
public static class RefinedEnvironmentReview
{
    [Serializable] sealed class Row
    {
        public string id;
        public int renderers, vertices, triangles, ambientNodes, curtains, foliage, distantTextures;
        public float observedClothOffset, observedSway, elapsed;
        public bool water, inactiveFrozen, pinnedCurtainTop, paletteBindingsValid;
    }
    [Serializable] sealed class Report { public int revision = 1; public Row[] environments; }
    public static void Rebuild() { BuildIos.Setup(); BuildIos.Validate(); Review(); SafeAreaFramingReview.Validate(); }
    public static void Thumbnails()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        EnvironmentPackageBuilder.Thumbnails();
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        Debug.Log("REFINED_ENVIRONMENT_THUMBNAILS_PASS");
    }
    public static void Review()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var director = UnityEngine.Object.FindFirstObjectByType<EnvironmentDirector>();
        if (!director || director.stages.Length != 6) throw new Exception("REFINED_ENVIRONMENT_SET_MISSING");
        director.Bind(1.7f);
        var rows = director.stages.Select(stage =>
        {
            director.Configure(new StudioSettings { room = stage.Manifest.id }, true);
            EnvironmentPackageBuilder.Validate(stage);
            var motion = stage.geometry.GetComponent<EnvironmentAmbientMotion>();
            if (!motion) throw new Exception("ENVIRONMENT_MOTION_MISSING: " + stage.Manifest.id);
            motion.Initialize();
            var row = new Row { id = stage.Manifest.id, renderers = motion.RendererCount, vertices = motion.VertexCount,
                ambientNodes = motion.ActiveNodes, curtains = motion.curtains.Length, foliage = motion.foliage.Length,
                water = motion.water, pinnedCurtainTop = true, paletteBindingsValid = true };
            foreach (var filter in stage.geometry.GetComponentsInChildren<MeshFilter>(true))
                if (filter.sharedMesh) row.triangles += filter.sharedMesh.triangles.Length / 3;
            foreach (var renderer in stage.geometry.GetComponentsInChildren<Renderer>(true))
            {
                if (!renderer.name.Contains("Distant scenery")) continue;
                if (renderer.sharedMaterial.GetTexture("_BaseMap")) row.distantTextures++;
                foreach (string binding in stage.Manifest.bindings.surface.Concat(stage.Manifest.bindings.accent))
                    if (renderer.transform.IsChildOf(stage.geometry.Find(binding))) row.paletteBindingsValid = false;
            }
            for (int frame = 0; frame < 180; frame++)
            {
                motion.Advance(1f / 60);
                row.observedClothOffset = Mathf.Max(row.observedClothOffset, motion.PeakClothOffset);
                row.observedSway = Mathf.Max(row.observedSway, motion.PeakSwayDegrees);
            }
            foreach (var curtain in motion.curtains)
            {
                if (!curtain.mesh) throw new Exception("ENVIRONMENT_CLOTH_MESH_MISSING");
                for (int i = 0; i < curtain.rest.Length; i++)
                    if (curtain.weights[i] == 0 && (curtain.vertices[i] - curtain.rest[i]).sqrMagnitude > .00000001f) row.pinnedCurtainTop = false;
            }
            foreach (var palette in stage.Manifest.palettes) stage.Apply(new EnvironmentSettings { palette = palette.id }, 0, true);
            stage.Apply(new EnvironmentSettings(), 0, true);
            row.elapsed = motion.Elapsed; stage.gameObject.SetActive(false); motion.Advance(.05f);
            row.inactiveFrozen = motion.Elapsed == row.elapsed;
            if (row.renderers > 256 || row.ambientNodes > 24 || row.ambientNodes == 0 || row.vertices > 250000 || row.distantTextures == 0
                || !row.inactiveFrozen || !row.pinnedCurtainTop || !row.paletteBindingsValid || row.observedSway <= .02f || row.observedSway > 2
                || (row.curtains > 0 && (row.observedClothOffset <= .001f || row.observedClothOffset > .027f)))
                throw new Exception("REFINED_ENVIRONMENT_INVALID: " + JsonUtility.ToJson(row));
            return row;
        }).ToArray();
        string folder = Path.Combine(CharacterPackageBuilder.Root, "docs/verification/refined-environments"); Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "geometry-motion.json"), JsonUtility.ToJson(new Report { environments = rows }, true) + "\n");
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        Debug.Log("REFINED_ENVIRONMENT_REVIEW_PASS: " + rows.Length + " coherent spaces, bounded local motion, no GPU rendering requested");
    }
}
