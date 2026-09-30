using System;
using System.IO;
using System.Linq;
using ModelSpace;
using UnityEngine;

// HOST-EMOTION-EXPERIMENT v1: opt-in three-character pilot. Source human maps,
// not matching names, calibrate anatomical axes from the actual standing pose.
public static class HostEmotionMotionBuilder
{
    [Serializable] sealed class Geometry {public Human[] human;}
    [Serializable] sealed class Human {public string human,path;}
    public static readonly string[] Actors={"anime-lime","anime-nozomi","anime-plum"};
    public static readonly string[] Joints={"Spine","Chest","Neck","Head","LeftShoulder","RightShoulder","LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm"};
    public static void Prepare(ViewerCharacter character,string folder)
    {
        if(!Actors.Contains(character.modelId))return;
        var geometry=JsonUtility.FromJson<Geometry>(File.ReadAllText(folder+"/avatar-geometry.json"));
        var rig=character.gameObject.AddComponent<HostEmotionRig>();
        rig.amplitude=character.modelId=="anime-plum"?.9f:1;
        // Verified controls that own a body pose, including platform selectors.
        rig.blockingParameters=new[]{"VRCEmote","ArmToggle","ArmBlendH","ArmBlendV","RockNRollStyle","StandStyle","CrouchStyle","ProneStyle","Seated","AFK","VelocityX","VelocityY","VelocityZ"};
        rig.joints=Joints.Select(human=>{
            string path=geometry.human.Single(h=>h.human==human).path;
            var bone=character.transform.Find("Avatar/"+path);
            if(!bone)throw new Exception("HOST_EMOTION_RIG_MISSING: "+character.modelId+"/"+human);
            Vector3 elbowAxis=Vector3.zero;
            if(human.EndsWith("LowerArm",StringComparison.Ordinal)) {
                var hand=character.transform.Find("Avatar/"+geometry.human.Single(h=>h.human==human.Replace("LowerArm","Hand")).path);
                var axis=Vector3.Cross((hand.position-bone.position).normalized,character.transform.forward).normalized;
                if(axis.sqrMagnitude<.9f)throw new Exception("HOST_EMOTION_ELBOW_PLANE_INVALID: "+human);
                elbowAxis=Quaternion.Inverse(bone.rotation)*axis;
            }
            return new HostEmotionRig.Joint {human=human,bone=bone,rest=bone.localRotation,elbowAxis=elbowAxis,
                lateralSign=Mathf.Sign(Vector3.Dot(bone.position-character.transform.Find("Avatar/"+geometry.human.Single(h=>h.human=="Chest").path).position,character.transform.right)),
                axes=Quaternion.Inverse(bone.rotation)*character.transform.rotation};
        }).ToArray();
    }
}
