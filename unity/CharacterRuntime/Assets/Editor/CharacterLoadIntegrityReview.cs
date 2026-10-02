using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEditor;
using UnityEngine;

// Data/engine regression, independent of paid AI and user conversation state.
public static class CharacterLoadIntegrityReview
{
    [Serializable] sealed class Row {public string id;public int skins,sourceOutsideActor,expanded;public bool visibilityPreserved,rejectedMissingMesh;}
    [Serializable] sealed class Report {public List<Row> characters=new List<Row>();}
    public static void Check()
    {
        var report=new Report();
        foreach(string id in CharacterPackageBuilder.Roster.characters)
        {
            string path="Assets/Prefabs/Package_"+id+".prefab";
            var prefab=AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if(!prefab)prefab=AssetDatabase.LoadAssetAtPath<GameObject>(CharacterBundleBuilder.Prefab(id));
            if(!prefab)throw new Exception("LOAD_REVIEW_PREFAB_MISSING: "+id);
            var instance=UnityEngine.Object.Instantiate(prefab);
            try {
                var actor=instance.GetComponent<ViewerCharacter>();actor.ApplyContract();
                var skins=instance.GetComponentsInChildren<SkinnedMeshRenderer>(true);
                var enabled=skins.Select(s=>s.enabled).ToArray();var active=skins.Select(s=>s.gameObject.activeSelf).ToArray();
                var bounds=skins.Select(s=>s.localBounds).ToArray();var envelope=actor.RestBounds();
                var row=new Row {id=id,skins=skins.Length};
                report.characters.Add(row);
                foreach(var skin in skins) {
                    var center=skin.transform.InverseTransformPoint(envelope.center);
                    if(!skin.localBounds.Contains(center))row.sourceOutsideActor++;
                }
                actor.PrepareRenderAssets();
                for(int i=0;i<skins.Length;i++) {
                    if(skins[i].localBounds.size!=bounds[i].size)row.expanded++;
                    if(!skins[i].localBounds.Contains(skins[i].transform.InverseTransformPoint(envelope.center)))
                        throw new Exception("LOAD_REVIEW_UNSAFE_CULLING: "+id);
                }
                row.visibilityPreserved=skins.Select(s=>s.enabled).SequenceEqual(enabled) && skins.Select(s=>s.gameObject.activeSelf).SequenceEqual(active);
                if(!row.visibilityPreserved)throw new Exception("LOAD_REVIEW_CHANGED_OUTFIT: "+id);
                // A partly missing prefab must fail before modelSelected/reveal.
                var original=skins[0].sharedMesh;skins[0].sharedMesh=null;
                try {actor.PrepareRenderAssets();}catch(InvalidOperationException) {row.rejectedMissingMesh=true;}
                finally {skins[0].sharedMesh=original;}
                if(!row.rejectedMissingMesh)throw new Exception("LOAD_REVIEW_ACCEPTED_PARTIAL_ACTOR: "+id);
            } finally {UnityEngine.Object.DestroyImmediate(instance);}
        }
        var output=Path.Combine(CharacterPackageBuilder.Root,".local/checks/character-load-integrity.json");
        Directory.CreateDirectory(Path.GetDirectoryName(output));File.WriteAllText(output,JsonUtility.ToJson(report,true)+"\n");
        Debug.Log("CHARACTER_LOAD_INTEGRITY_PASS characters="+report.characters.Count+" skins="+report.characters.Sum(c=>c.skins));
    }
}
