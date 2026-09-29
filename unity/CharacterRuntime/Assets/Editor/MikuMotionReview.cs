using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class MikuMotionReview
{
    public static void ValidateAndCapture()
    {
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
        var viewer=UnityEngine.Object.FindFirstObjectByType<ViewerController>();
        var character=viewer.characters.Single(c=>c.modelId=="hatsune-miku");
        foreach(var c in viewer.characters)c.gameObject.SetActive(c==character);
        var animation=character.GetComponent<Animation>();var spring=character.GetComponent<MikuSecondaryMotion>();
        var named=character.GetComponentsInChildren<Transform>(true).ToDictionary(t=>t.name,t=>t);
        string folder=Path.GetFullPath("../../.local/checks/miku-motion-review");Directory.CreateDirectory(folder);
        var camera=viewer.viewCamera;var bounds=character.RestBounds();camera.aspect=1;
        float distance=OrbitMath.FitDistance(bounds,1,camera.fieldOfView)*.86f;
        int frames=0;float closestHands=float.MaxValue,maxFootError=0,maxHeadHandOverlap=0,minForearmClearance=float.MaxValue;
        foreach(string action in new[]{"Idle","Wave","Jump","Dance","Bow","Spin","Greet","Cheer","No"})
        {
            var clip=animation.GetClip(action);spring.ResetSimulation();int n=Mathf.CeilToInt(clip.length*120);
            for(int f=0;f<=n;f++)
            {
                clip.SampleAnimation(character.gameObject,clip.length*f/n);spring.Step(1f/120);frames++;
                foreach(var t in named.Values)if(float.IsNaN(t.position.sqrMagnitude))throw new Exception("Non-finite pose "+action);
                float hands=Vector3.Distance(named["左手首"].position,named["右手首"].position);closestHands=Mathf.Min(closestHands,hands);
                if(hands<.75f)throw new Exception("Hands intersect "+action+" time="+clip.length*f/n);
                foreach(string side in new[]{"左","右"})
                {
                    float headDistance=Vector3.Distance(named[side+"手首"].position,named["頭"].position);
                    Vector3 chestA=named["上半身"].position,chestB=named["首"].position;
                    Vector3 axis=chestB-chestA;
                    for(int probe=0;probe<=8;probe++)
                    {
                        var pt=Vector3.Lerp(named[side+"ひじ"].position,named[side+"手首"].position,probe/8f);
                        var nearest=chestA+axis*Mathf.Clamp01(Vector3.Dot(pt-chestA,axis)/axis.sqrMagnitude);
                        float clearance=Vector3.Distance(pt,nearest)-.42f;
                        minForearmClearance=Mathf.Min(minForearmClearance,clearance);
                        if(clearance<0)throw new Exception("Forearm enters torso envelope "+action+" time="+clip.length*f/n);
                    }
                    maxHeadHandOverlap=Mathf.Max(maxHeadHandOverlap,.48f-headDistance);
                    if(headDistance<.48f)throw new Exception("Hand enters head envelope "+action);
                    if(action!="Spin")
                    {
                        Vector3 foot=named["全ての親"].InverseTransformPoint(named[side+"足首D"].position);
                        maxFootError=Mathf.Max(maxFootError,Mathf.Abs(foot.y-.202f));
                    }
                }
                // Check the whole pose at three phases, from three directions, including hair follow-through.
                if(f==Mathf.RoundToInt(n*.20f)||f==Mathf.RoundToInt(n*.50f)||f==Mathf.RoundToInt(n*.80f))
                {
                    foreach(int yaw in new[]{155,90,0})
                    {
                        camera.transform.position=bounds.center+Quaternion.Euler(12,yaw,0)*Vector3.back*distance;camera.transform.LookAt(bounds.center);
                        CharacterVisualReview.Render(camera,Path.Combine(folder,action+"-"+Mathf.RoundToInt(100f*f/n)+"-"+yaw+".png"),640);
                    }
                }
            }
        }
        if(maxFootError>.012f)throw new Exception("Foot plant error "+maxFootError);
        File.WriteAllText(Path.Combine(folder,"validation.json"),"{\"status\":\"PASS\",\"sampledFrames\":"+frames+",\"sampleHz\":120,\"minimumHandSeparation\":"+closestHands+",\"maxAnkleHeightError\":"+maxFootError+",\"minimumForearmTorsoClearance\":"+minForearmClearance+",\"headHandEnvelopeOverlap\":"+maxHeadHandOverlap+",\"scope\":\"Finite poses, hand separation, head envelope and ankle planting; not an exhaustive triangle intersection proof\"}");
        EditorSceneManager.OpenScene("Assets/Scenes/ViewerScene.unity");
    }
}
