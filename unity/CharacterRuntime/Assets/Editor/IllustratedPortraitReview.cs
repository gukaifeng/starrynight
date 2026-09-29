using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class IllustratedPortraitReview
{
    [Serializable] sealed class Row
    {
        public string id;
        public int vertices,triangles,materialSlots,springSegments;
        public float hairMotion,headMotion;
        public bool softShadows,alphaGlass;
    }
    [Serializable] sealed class Report { public Row[] characters; }
    public static void Rebuild() { BuildIos.Setup();BuildIos.Validate();Review(); }
    public static void Review()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var selected=viewer.characters.Where(c=>new[]{"anime-uka","anime-velara","anime-onyx"}.Contains(c.modelId)).ToArray();
        if(selected.Length!=3)throw new Exception("ILLUSTRATED_CHARACTERS_MISSING");
        string folder=Path.Combine(CharacterPackageBuilder.Root,"docs/verification/illustrated-portraits");Directory.CreateDirectory(folder);
        var rows=selected.Select(c=>{
            foreach(var other in viewer.characters)other.gameObject.SetActive(other==c);
            var studio=viewer.GetComponent<CharacterStudioDriver>();studio.Bind(c);studio.Configure(new StudioSettings(),true);
            var player=c.GetComponentInChildren<Animation>();var idle=player.GetClip("Idle");
            var motion=c.GetComponent<AvatarSecondaryMotion>();motion.ResetSimulation();idle.SampleAnimation(c.gameObject,0);
            var head=CharacterContract.Resolve(c.transform,c.Manifest.rig.head);var headRest=head.localRotation;
            var hair=motion.strands.Where(s=>s.bone.name.Contains("Hair") || s.bone.name.Contains("髪")).ToArray();
            var rest=hair.Select(s=>s.bone.localRotation).ToArray();
            var row=new Row {id=c.modelId,springSegments=motion.strands.Length,softShadows=studio.key.shadows==LightShadows.Soft};
            foreach(var skin in c.GetComponentsInChildren<SkinnedMeshRenderer>())
            {
                row.vertices+=skin.sharedMesh.vertexCount;row.triangles+=skin.sharedMesh.triangles.Length/3;
                row.materialSlots+=skin.sharedMaterials.Length;
                foreach(var m in skin.sharedMaterials)if(m.name.Contains("Lens"))
                    row.alphaGlass=m.shader.name=="Universal Render Pipeline/Lit" && m.GetFloat("_Surface")==1 && m.GetFloat("_ZWrite")==0;
            }
            for(int frame=0;frame<720;frame++)
            {
                idle.SampleAnimation(c.gameObject,frame/60f);motion.Step(1f/60);
                row.headMotion=Mathf.Max(row.headMotion,Quaternion.Angle(headRest,head.localRotation));
                for(int i=0;i<hair.Length;i++)row.hairMotion=Mathf.Max(row.hairMotion,Quaternion.Angle(rest[i],hair[i].bone.localRotation));
            }
            if(!row.softShadows || row.hairMotion<.1f || row.hairMotion>20 || row.headMotion<.1f)
                throw new Exception("ILLUSTRATION_MOTION_INVALID: "+JsonUtility.ToJson(row));
            if(c.modelId!="anime-uka" && !row.alphaGlass)throw new Exception("ILLUSTRATION_LENS_INVALID");
            motion.ResetSimulation();idle.SampleAnimation(c.gameObject,0);
            return row;
        }).ToArray();
        File.WriteAllText(Path.Combine(folder,"runtime-content.json"),JsonUtility.ToJson(new Report {characters=rows},true));
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        BuildIos.Thumbnail();CharacterPortraitBuilder.Export();
        Debug.Log("ILLUSTRATED_PORTRAITS_REVIEW_PASS");
    }
}
