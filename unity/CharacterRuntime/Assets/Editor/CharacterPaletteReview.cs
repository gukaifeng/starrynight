using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

// Real source prefabs, all material slots including hidden author variants.
// This audit is separate from Metal player rendering and real device FPS.
public static class CharacterPaletteReview
{
    [Serializable] class Row {public string id;public int components,hidden,channels,families;}
    [Serializable] class Report {public string status="PASS";public int assertions;public List<Row> characters=new List<Row>();}
    static Report report;
    static void Check(bool value,string message) {if(!value)throw new Exception("PALETTE_REVIEW: "+message);report.assertions++;}
    public static void Run()
    {
        CharacterPaletteBuilder.Prepare();report=new Report();
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        foreach(var source in viewer.characters)
        {
            var instance=UnityEngine.Object.Instantiate(source.gameObject);instance.SetActive(true);
            try
            {
                var palette=instance.AddComponent<CharacterPaletteRuntime>();
                // Awake is not invoked when an ordinary MonoBehaviour is added
                // in Edit Mode; explicitly invoke that same initialization.
                palette.SendMessage("Awake");
                var snapshot=palette.Snapshot(source.modelId);
                var renderers=instance.GetComponentsInChildren<Renderer>(true);
                int expected=renderers.Sum(r=>r.sharedMaterials.Count(m=>m));
                Check(snapshot.components.Length==expected,"all slots "+source.modelId);
                Check(snapshot.components.Select(x=>x.id).Distinct().Count()==expected,"stable unique slots "+source.modelId);
                var originals=renderers.Select(r=>r.sharedMaterials).ToArray();
                var originalColors=originals.SelectMany(x=>x).Where(x=>x).Distinct().ToDictionary(m=>m,m=>Enumerable.Range(0,m.shader.GetPropertyCount()).Where(i=>m.shader.GetPropertyType(i)==ShaderPropertyType.Color).ToDictionary(i=>m.shader.GetPropertyName(i),i=>m.GetColor(m.shader.GetPropertyName(i))));
                foreach(var slot in snapshot.components)
                {
                    Check(slot.supported,"supported shader "+source.modelId+" "+slot.shader);
                    Check(slot.channels.Length>0,"color channel inventory "+slot.id);
                    foreach(var band in new[]{"$main","$shadow","$highlight"})
                        palette.Edit(new PaletteEdit {component=slot.id,channel=band,tone=new PaletteTone {hue=27.5f,saturation=.72f,exposure=.35f,tint=.15f}});
                    foreach(var channel in slot.channels)
                    {
                        palette.Edit(new PaletteEdit {component=slot.id,channel=channel.id,tone=new PaletteTone {hue=-42.1f,saturation=1.12f,exposure=.1f,tint=.06f}});
                        var graded=CharacterPaletteRuntime.GradeColor(channel.color,new Vector4(.1f,1.1f,.2f,.1f));
                        Check(graded.a==channel.color.a,"alpha retained "+channel.id);
                        Check(CharacterPaletteRuntime.GradeColor(channel.color,CharacterPaletteRuntime.Neutral)==channel.color,"neutral exact "+channel.id);
                    }
                }
                palette.Tick(1);
                Check(palette.EditedSlots==expected,"independent material instances "+source.modelId);
                // A repeated LateUpdate must not re-grade its own MPB result.
                // Unity color flags/linear conversion make this an important
                // real-engine test rather than a mirrored HSV unit test.
                var stable=new MaterialPropertyBlock();
                renderers[0].GetPropertyBlock(stable,0);
                Color stableColor=stable.GetColor("_Color");
                for(int n=0;n<120;n++)palette.Tick(1);
                renderers[0].GetPropertyBlock(stable,0);
                Check(((Vector4)(stable.GetColor("_Color")-stableColor)).sqrMagnitude<1e-8f,"no cumulative grading drift "+source.modelId);
                foreach(var item in originalColors)foreach(var color in item.Value)Check(item.Key.GetColor(color.Key)==color.Value,"source unchanged "+color.Key);
                var first=snapshot.components[0];
                bool rejected=false;
                try {palette.Edit(new PaletteEdit {component=first.id,channel="$main",tone=new PaletteTone {hue=float.NaN}});}catch(ArgumentException) {rejected=true;}
                Check(rejected,"reject nonfinite");
                // Another runtime component's MPB survives both grading and reset.
                var sentinel=new MaterialPropertyBlock();renderers[0].GetPropertyBlock(sentinel,0);sentinel.SetFloat("_StarryReviewSentinel",.413f);renderers[0].SetPropertyBlock(sentinel,0);
                palette.Reset(null);palette.Tick(2);
                renderers[0].GetPropertyBlock(sentinel,0);Check(Mathf.Abs(sentinel.GetFloat("_StarryReviewSentinel")-.413f)<1e-6,"preserve unrelated block");
                for(int i=0;i<renderers.Length;i++)Check(renderers[i].sharedMaterials.SequenceEqual(originals[i]),"exact materials restored "+source.modelId);
                Check(palette.EditedSlots==0,"no clone leaks after reset");
                // Animator material swaps keep the authored new material as the
                // reset target; grading never forces a previous outfit back.
                var targetRenderer=renderers.First(r=>r.sharedMaterials.Length>0 && r.sharedMaterials[0]);
                var replacement=new Material(targetRenderer.sharedMaterials[0]);
                var targeted=snapshot.components.First(x=>x.path==RelativePath(instance.transform,targetRenderer.transform) && x.slot==0);
                palette.Edit(new PaletteEdit {component=targeted.id,channel="$main",tone=new PaletteTone {hue=24}});
                var changed=targetRenderer.sharedMaterials;changed[0]=replacement;targetRenderer.sharedMaterials=changed;
                palette.Tick(1);Check(targetRenderer.sharedMaterials[0]!=replacement,"adopt animated swap");
                palette.Reset(targeted.id);palette.Tick(2);Check(targetRenderer.sharedMaterials[0]==replacement,"reset to latest authored swap");
                changed=targetRenderer.sharedMaterials;changed[0]=originals[Array.IndexOf(renderers,targetRenderer)][0];targetRenderer.sharedMaterials=changed;
                UnityEngine.Object.DestroyImmediate(replacement);
                report.characters.Add(new Row {id=source.modelId,components=expected,hidden=snapshot.components.Count(x=>!x.visible),channels=snapshot.components.Sum(x=>x.channels.Length),families=snapshot.components.Select(x=>x.shader).Distinct().Count()});
            }
            finally {UnityEngine.Object.DestroyImmediate(instance);}
        }
        string output=Path.GetFullPath(Path.Combine(Application.dataPath,"../../../.local/checks/palette-v098"));Directory.CreateDirectory(output);
        File.WriteAllText(output+"/all-roles.json",JsonUtility.ToJson(report,true));
        Debug.Log("PALETTE_REVIEW_PASS roles="+report.characters.Count+" assertions="+report.assertions+" slots="+report.characters.Sum(x=>x.components)+" channels="+report.characters.Sum(x=>x.channels));
    }
    public static void ReviewAndExportSimulator() {Run();CharacterPaletteBuilder.ExportSimulator();}
    static string RelativePath(Transform root,Transform t)
    {var items=new List<string>();while(t && t!=root){items.Add(t.name+"["+t.GetSiblingIndex()+"]");t=t.parent;}items.Reverse();return string.Join("/",items);}
}
