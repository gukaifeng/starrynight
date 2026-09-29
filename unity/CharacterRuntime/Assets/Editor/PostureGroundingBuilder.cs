using System;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;
using ModelSpace;
public static class PostureGroundingBuilder
{
    public static void Build(ViewerCharacter c)
    {
        var profile=c.Manifest.posture;if(profile==null || profile.poses.Length==0)return;
        var guard=c.GetComponent<PostureGrounding>() ?? c.gameObject.AddComponent<PostureGrounding>();
        // Lowest common parent of all animated body nodes, including rigid feet.
        var bones=profile.bones.Select(p=>c.transform.Find(p)).ToArray();
        var pivot=bones[0];while(pivot.parent!=c.transform && bones.Any(t=>t!=pivot && !t.IsChildOf(pivot)))pivot=pivot.parent;
        // One extra unanimated parent keeps independent rigid foot nodes in the same correction.
        if(pivot.parent && pivot.parent!=c.transform)pivot=pivot.parent;
        guard.pivot=pivot;
        var renderers=c.GetComponentsInChildren<Renderer>(true);
        var selected=new Dictionary<Renderer,HashSet<int>>();foreach(var r in renderers)selected[r]=new HashSet<int>();
        var player=c.GetComponent<Animation>();var baked=new Mesh();
        void Sample()
        {
            var low=new List<(Renderer r,int index,float y)>();float minimum=float.PositiveInfinity;
            foreach(var r in renderers)
            {
                Mesh mesh;if(r is SkinnedMeshRenderer skin){skin.BakeMesh(baked,true);mesh=baked;}else mesh=r.GetComponent<MeshFilter>()?.sharedMesh;
                if(!mesh)continue;
                var vertices=mesh.vertices;float y=float.PositiveInfinity;int index=0;
                for(int i=0;i<vertices.Length;i++){float h=r.transform.TransformPoint(vertices[i]).y;if(h<y){y=h;index=i;}}
                minimum=Mathf.Min(minimum,y);low.Add((r,index,y));
            }
            foreach(var v in low)if(v.y<minimum+.035f)selected[v.r].Add(v.index);
        }
        foreach(string clip in profile.Clips){player.GetClip(clip).SampleAnimation(c.gameObject,0);Sample();}
        foreach(var from in profile.poses)foreach(var to in profile.poses)
        {
            if(from==to)continue;
            player.GetClip(from.clip).SampleAnimation(c.gameObject,0);var a=bones.Select(t=>t.localPosition).ToArray();var ar=bones.Select(t=>t.localRotation).ToArray();
            player.GetClip(to.clip).SampleAnimation(c.gameObject,0);var b=bones.Select(t=>t.localPosition).ToArray();var br=bones.Select(t=>t.localRotation).ToArray();
            for(int step=0;step<=32;step++)
            {
                float t=step/32f;
                for(int j=0;j<bones.Length;j++){bones[j].localPosition=Vector3.Lerp(a[j],b[j],t);bones[j].localRotation=Quaternion.Slerp(ar[j],br[j],t);}Sample();
            }
        }
        var probes=new List<GroundProbe>();
        foreach(var pair in selected)
        {
            if(pair.Key is SkinnedMeshRenderer skin)
            {
                var mesh=skin.sharedMesh;var positions=mesh.vertices;var weights=mesh.boneWeights;var poses=mesh.bindposes;var rig=skin.bones;
                foreach(int index in pair.Value)
                {
                    var w=weights[index];var v=positions[index];
                    probes.Add(new GroundProbe {a=rig[w.boneIndex0],b=w.weight1>0?rig[w.boneIndex1]:null,c=w.weight2>0?rig[w.boneIndex2]:null,d=w.weight3>0?rig[w.boneIndex3]:null,
                        pa=poses[w.boneIndex0].MultiplyPoint3x4(v),pb=w.weight1>0?poses[w.boneIndex1].MultiplyPoint3x4(v):Vector3.zero,pc=w.weight2>0?poses[w.boneIndex2].MultiplyPoint3x4(v):Vector3.zero,pd=w.weight3>0?poses[w.boneIndex3].MultiplyPoint3x4(v):Vector3.zero,
                        weights=new Vector4(w.weight0,w.weight1,w.weight2,w.weight3)});
                }
            }
            else if(pair.Key.GetComponent<MeshFilter>() is MeshFilter filter)
                foreach(int index in pair.Value)probes.Add(new GroundProbe{a=pair.Key.transform,pa=filter.sharedMesh.vertices[index],weights=new Vector4(1,0,0,0)});
        }
        if(probes.Count>256)throw new Exception("POSTURE_GROUND_PROBE_BUDGET: "+c.modelId+"/"+probes.Count);
        guard.probes=probes.ToArray();UnityEngine.Object.DestroyImmediate(baked);player.GetClip("Idle").SampleAnimation(c.gameObject,0);
    }
}
