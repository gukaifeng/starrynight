using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using ModelSpace;
using UnityEngine;

// HOST-EMOTION-EXPERIMENT v2: developer-only universal pilot. Source human maps,
// not matching names, calibrate anatomical axes from the actual standing pose.
public static class HostEmotionMotionBuilder
{
    [Serializable] sealed class Geometry {public Human[] human;}
    [Serializable] sealed class Human {public string human,path;}
    public static string[] Actors=>CharacterPackageBuilder.Roster.characters;
    public static readonly string[] Joints={"Spine","Chest","Neck","Head","LeftShoulder","RightShoulder","LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm"};
    public static void Prepare(ViewerCharacter character,string folder)
    {
        if(!File.Exists(folder+"/avatar-geometry.json"))return;
        var geometry=JsonUtility.FromJson<Geometry>(File.ReadAllText(folder+"/avatar-geometry.json"));
        if(Joints.Concat(new[]{"LeftHand","RightHand"}).Any(h=>!geometry.human.Any(b=>b.human==h && character.transform.Find("Avatar/"+b.path))))return;
        var rig=character.gameObject.AddComponent<HostEmotionRig>();
        rig.amplitude=1;
        Transform HumanBone(string h){var item=geometry.human.FirstOrDefault(b=>b.human==h);return item==null?null:character.transform.Find("Avatar/"+item.path);}
        rig.leftFoot=HumanBone("LeftFoot");rig.rightFoot=HumanBone("RightFoot");rig.leftHand=HumanBone("LeftHand");rig.rightHand=HumanBone("RightHand");
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
        // Use the mapped wrists when available. No author-specific bone names.
        rig.joints=rig.joints.Concat(new[]{"LeftHand","RightHand"}.Select(human=>{
            var bone=character.transform.Find("Avatar/"+geometry.human.Single(h=>h.human==human).path);
            return new HostEmotionRig.Joint {human=human,bone=bone,rest=bone.localRotation,axes=Quaternion.Inverse(bone.rotation)*character.transform.rotation};
        })).ToArray();
        if(!File.Exists(folder+"/source-motions.json.gz"))return;
        var library=JsonUtility.FromJson<SourceMotionLibraryBuilder.Library>(CharacterMotionData.Read(folder+"/source-motions.json"));
        var excluded=character.Manifest.speech.visemes.SelectMany(v=>v.bindings).Concat(character.Manifest.speech.amplitude).Select(b=>b.renderer+"/"+b.shape).ToHashSet();
        string Intent(string gesture)=>gesture=="agree" || gesture=="happy" || gesture=="welcome" || gesture=="encourage"?"soft_smile":gesture=="disagree"?"pout":gesture=="curious"?"confused":gesture;
        rig.faces=HostEmotionMotion.Gestures.Select(gesture=>{
            string intent=Intent(gesture);
            bool Face(SourceMotionLibraryBuilder.Motion m)=>m.curves.Any(c=>"Avatar/"+c.path==character.Manifest.rig.headRenderer && c.property.StartsWith("blendShape.") && !excluded.Contains("Avatar/"+c.path+"/"+c.property.Substring(11)) && c.keys.Any(k=>k.value>5));
            string Alias(SourceMotionLibraryBuilder.Motion m){
                string n=m.name.ToLowerInvariant();
                if(Regex.IsMatch(n,@"shock|surpris|donbiki|驚|惊|びっくり|^!$|marushiro"))return "surprised";
                if(Regex.IsMatch(n,@"zitome|ジト|じと|sulk|pout|angry|^han$"))return "pout";
                return m.intent;
            }
            var candidates=library.motions.Where(Face).OrderBy(m=>m.duration).ToArray();
            var source=candidates.FirstOrDefault(m=>Alias(m)==intent);
            bool approximate=false;
            // Some authors provide only a small face palette. A gentle authored
            // smile can accompany a shy/curious gesture; mark this as a match
            // approximation rather than pretending the author shipped that mood.
            if(source==null){
                string[] fallback=intent=="shy" || intent=="confused"?new[]{"soft_smile","playful"}:
                    intent=="surprised"?new[]{"confused","playful","soft_smile"}:Array.Empty<string>();
                foreach(string next in fallback){source=candidates.FirstOrDefault(m=>Alias(m)==next);if(source!=null){approximate=true;break;}}
            }
            if(source==null)return new HostEmotionRig.Face {gesture=gesture,label="中性表情（原包无可靠匹配）"};
            var curves=source.curves.Where(c=>"Avatar/"+c.path==character.Manifest.rig.headRenderer && c.property.StartsWith("blendShape.") && !excluded.Contains("Avatar/"+c.path+"/"+c.property.Substring(11))).Take(64).ToArray();
            var skins=curves.Select(c=>character.transform.Find("Avatar/"+c.path).GetComponent<SkinnedMeshRenderer>()).ToArray();
            var indices=curves.Select((c,i)=>skins[i].sharedMesh.GetBlendShapeIndex(c.property.Substring(11))).ToArray();
            return new HostEmotionRig.Face {gesture=gesture,label=source.name+(approximate?"（近似配合）":""),skins=skins,indices=indices,
                values=curves.Select((c,i)=>Mathf.Clamp(c.keys.Select(k=>k.value).DefaultIfEmpty(0).Max(),0,100)*CharacterContract.MorphScale(skins[i],indices[i])/100).ToArray()};
        }).ToArray();
    }
}
