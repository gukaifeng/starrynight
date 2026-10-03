using System;
using System.Collections.Generic;
using UnityEngine;

namespace ModelSpace
{
    [Serializable] public sealed class AvatarNaturalMotionState
    {
        public int revision=1,joints,fingers;
        public bool supported,suppressed,speaking,legacyCalibration;
        public float weight,breath,peakDegrees,handTravel,footError;
        public string origin="starrynight.host-natural-body.v1";
        public AvatarClothingClearanceState clothing;
    }

    // Host-only additive body life. Author animations stay authoritative. This
    // layer does NOT turn humanoid limbs into PhysBones or a ragdoll.
    // Apply after continuity/gaze, before emotional gestures and cloth springs.
    [DefaultExecutionOrder(85)]
    public sealed class AvatarNaturalMotion:MonoBehaviour
    {
        sealed class Joint
        {
            public string human;public Transform bone;public Quaternion axes,elbow,rawRotation;
            public Vector3 rawPosition;public float side;
        }
        Joint[] joints=Array.Empty<Joint>();
        readonly Dictionary<string,Joint> map=new Dictionary<string,Joint>();
        ViewerCharacter actor;CharacterActions actions;AvatarControlDriver author;HostEmotionMotion emotion;
        CharacterPerformanceDriver performance;
        HostEmotionRig rig;float clock,phase,weight,weightVelocity,height=1;
        AvatarClothingClearance clothing;
        float leftWeight=1,rightWeight=1,leftVelocity,rightVelocity;
        bool applied;
        public AvatarNaturalMotionState State {get;private set;}=new AvatarNaturalMotionState();
        public void Bind(ViewerCharacter character,CharacterActions source,CharacterPerformanceDriver overlay,HostEmotionMotion gestures)
        {
            Clear();actor=character;actions=source;performance=overlay;emotion=gestures;
            rig=character.GetComponent<HostEmotionRig>();author=character.GetComponent<AvatarControlDriver>();
            if(!rig)return;
            var list=new List<HostEmotionRig.Joint>(rig.joints);
            list.AddRange(rig.naturalJoints??Array.Empty<HostEmotionRig.Joint>());
            State.legacyCalibration=rig.naturalJoints==null || rig.naturalJoints.Length==0;
            // v2/v3 OSS calibration contains both actual feet. Direct chains are
            // accepted only when both thighs share the same hips transform.
            if(State.legacyCalibration && rig.leftFoot && rig.rightFoot) {
                var lh=rig.leftFoot.parent?.parent?.parent;var rh=rig.rightFoot.parent?.parent?.parent;
                if(lh && lh==rh) {
                    void Add(string name,Transform bone){list.Add(new HostEmotionRig.Joint {human=name,bone=bone,rest=bone.localRotation,axes=Quaternion.Inverse(bone.rotation)*actor.transform.rotation});}
                    Add("Hips",lh);
                    foreach(string side in new[]{"Left","Right"}) {
                        var foot=side=="Left"?rig.leftFoot:rig.rightFoot;
                        Add(side+"UpperLeg",foot.parent.parent);Add(side+"LowerLeg",foot.parent);Add(side+"Foot",foot);
                    }
                }
            }
            foreach(var sourceJoint in list)if(sourceJoint.bone && !map.ContainsKey(sourceJoint.human)) {
                var j=new Joint {human=sourceJoint.human,bone=sourceJoint.bone,axes=sourceJoint.axes,
                    elbow=sourceJoint.elbowAxis.sqrMagnitude>.9f?Quaternion.FromToRotation(Vector3.right,sourceJoint.elbowAxis):Quaternion.identity,
                    side=sourceJoint.lateralSign};
                map.Add(j.human,j);
            }
            joints=new List<Joint>(map.Values).ToArray();
            State.supported=map.ContainsKey("Chest") && map.ContainsKey("LeftUpperArm") && map.ContainsKey("RightUpperArm");
            State.joints=joints.Length;State.fingers=Array.FindAll(joints,j=>j.human.EndsWith("Proximal")).Length;
            height=Mathf.Max(.2f,actor.RestBounds().size.y*actor.transform.lossyScale.y);
            clothing=character.GetComponent<AvatarClothingClearance>()??character.gameObject.AddComponent<AvatarClothingClearance>();
            clothing.Initialize(character,rig);State.clothing=clothing.State;
            int seed=17;foreach(char ch in character.modelId)seed=unchecked(seed*31+ch);
            phase=(seed & 65535)/65535f*Mathf.PI*2;
            var restore=GetComponent<AvatarNaturalMotionRestore>()??gameObject.AddComponent<AvatarNaturalMotionRestore>();restore.driver=this;
        }
        public void Clear(){if(clothing)clothing.Release();Restore();clothing=null;actor=null;rig=null;map.Clear();joints=Array.Empty<Joint>();clock=weight=weightVelocity=0;leftWeight=rightWeight=1;leftVelocity=rightVelocity=0;State=new AvatarNaturalMotionState();}
        public void SetSpeech(bool value){State.speaking=value;}
        public void Restore()
        {
            if(!applied)return;
            foreach(var j in joints)if(j.bone){j.bone.localRotation=j.rawRotation;j.bone.localPosition=j.rawPosition;}
            applied=false;
        }
        void OnDisable(){Clear();}
        void LateUpdate(){Step(Time.unscaledDeltaTime);}
        bool Blocked()
        {
            if(!actor || !actor.gameObject.activeInHierarchy)return true;
            if(actor.GetComponent<SourceMotionPreview>()?.Active==true)return true;
            if(actions && (!string.IsNullOrEmpty(actions.CurrentAction) || (actions.Posture && (actions.Posture.State.id!="stand" || actions.Posture.State.transitioning))))return true;
            if(performance && performance.WeightFor(new[]{"pose"},null)>.05f)return true;
            if(author)foreach(string name in rig.blockingParameters) {
                var p=Array.Find(author.profile.parameters,v=>v.name==name);
                if(p!=null && Mathf.Abs(author.Get(name)-p.initial)>.001f)return true;
            }
            return false;
        }
        float ArmAvailability(string side)
        {
            if(emotion && emotion.State.gesture.Length>0)return 0;
            if(author && author.Get("Gesture"+side)>0)return 0;
            if(!map.TryGetValue(side+"UpperArm",out var upper) || !map.TryGetValue(side+"Hand",out var hand))return 0;
            return Mathf.InverseLerp(.55f,.8f,Vector3.Dot((hand.bone.position-upper.bone.position).normalized,-actor.transform.up));
        }
        public void Step(float dt)
        {
            Restore();
            if(!State.supported || !actor || !float.IsFinite(dt) || dt<=0)return;
            clothing.CaptureBaseline();
            if(dt>.15f){weightVelocity=leftVelocity=rightVelocity=0;dt=1f/60;}
            dt=Mathf.Min(dt,.05f);clock+=dt;
            bool blocked=Blocked();State.suppressed=blocked;
            weight=Mathf.SmoothDamp(weight,blocked?0:1,ref weightVelocity,.38f,10,dt);State.weight=weight;
            leftWeight=Mathf.SmoothDamp(leftWeight,ArmAvailability("Left"),ref leftVelocity,.32f,10,dt);
            rightWeight=Mathf.SmoothDamp(rightWeight,ArmAvailability("Right"),ref rightVelocity,.32f,10,dt);
            if(weight<.00001f)return;
            foreach(var j in joints){j.rawRotation=j.bone.localRotation;j.rawPosition=j.bone.localPosition;}
            var lf=map.TryGetValue("LeftFoot",out var l)?l.bone:null;var rf=map.TryGetValue("RightFoot",out var r)?r.bone:null;
            Vector3 lp=lf?lf.position:Vector3.zero,rp=rf?rf.position:Vector3.zero;
            Quaternion lr=lf?lf.rotation:Quaternion.identity,rr=rf?rf.rotation:Quaternion.identity;
            Vector3 lh=rig.leftHand?rig.leftHand.position:Vector3.zero,rh=rig.rightHand?rig.rightHand.position:Vector3.zero;
            float breath=Mathf.Sin(clock*1.36f+phase+.13f*Mathf.Sin(clock*.23f));State.breath=breath;
            float sway=.75f*Mathf.Sin(clock*.57f+phase)+.25f*Mathf.Sin(clock*.93f+phase*1.7f);
            float detail=Mathf.Sin(clock*.83f+phase*.7f);
            float emphasis=State.speaking?1.12f:1;
            if(map.TryGetValue("Hips",out var hips) && lf && rf) {
                // A millimetre-scale weight transfer drives the knees/ankles;
                // solve to the author's CURRENT foot contacts, not world locks.
                hips.bone.position+=actor.transform.right*(height*.002f*sway*weight)-actor.transform.up*(height*.0015f*(1.2f+.5f*breath)*weight);
            }
            foreach(var j in joints) {
                Vector3 e=Vector3.zero;float arm=j.human.StartsWith("Left")?leftWeight:rightWeight;
                switch(j.human) {
                    case "Spine":e=new Vector3(.65f*breath,.32f*sway,.38f*sway);break;
                    case "Chest":e=new Vector3(.85f*breath,.45f*sway,.48f*sway);break;
                    case "Neck":e=new Vector3(-.25f*breath,.28f*detail,-.24f*sway);break;
                    case "Head":e=new Vector3(-.3f*breath,.65f*detail,-.38f*sway);break;
                    case "LeftShoulder":case "RightShoulder":e=new Vector3(.4f*breath,0,j.side*.65f*breath)*arm;break;
                    case "LeftUpperArm":case "RightUpperArm": {
                        // Keep the author's sleeve clearance. A universal seven
                        // degree adduction made wide sleeves enter the torso.
                        e=new Vector3(1.5f*sway+.45f*breath,.5f*detail,-j.side*.8f*breath)*arm;break;
                    }
                    case "LeftLowerArm":case "RightLowerArm": {
                        var upper=map[j.human.Replace("LowerArm","UpperArm")].bone;var hand=map[j.human.Replace("LowerArm","Hand")].bone;
                        float flex=180-Vector3.Angle(upper.position-j.bone.position,hand.position-j.bone.position);
                        float angle=(Mathf.Clamp(12-flex,0,10)+1.4f+.9f*breath)*arm*weight;
                        var axis=j.elbow*Vector3.right;j.bone.localRotation=j.rawRotation*Quaternion.AngleAxis(angle,axis);
                        State.peakDegrees=Mathf.Max(State.peakDegrees,angle);continue;
                    }
                    case "LeftHand":case "RightHand":e=new Vector3(.55f*breath,.9f*detail,j.side*1.5f*sway)*arm;break;
                    default:
                        if(j.human.EndsWith("Proximal")) {
                            // Tiny finger life only: no fist synthesis or guessed
                            // finger axes. Calibrated whole-character coordinates.
                            e=new Vector3(.65f*breath,0,.25f*detail)*arm;
                        }
                        break;
                }
                e*=weight*emphasis;State.peakDegrees=Mathf.Max(State.peakDegrees,e.magnitude);
                j.bone.localRotation=j.rawRotation*(j.axes*Quaternion.Euler(e)*Quaternion.Inverse(j.axes));
            }
            if(lf && rf && map.ContainsKey("Hips")) {
                SolveLeg("Left",lp,lr);SolveLeg("Right",rp,rr);
                State.footError=Mathf.Max(State.footError,Vector3.Distance(lf.position,lp),Vector3.Distance(rf.position,rp));
            }
            if(rig.leftHand)State.handTravel=Mathf.Max(State.handTravel,Vector3.Distance(lh,rig.leftHand.position));
            if(rig.rightHand)State.handTravel=Mathf.Max(State.handTravel,Vector3.Distance(rh,rig.rightHand.position));
            applied=true;
        }
        void SolveLeg(string side,Vector3 target,Quaternion footRotation)
        {
            if(!map.TryGetValue(side+"UpperLeg",out var u) || !map.TryGetValue(side+"LowerLeg",out var k) || !map.TryGetValue(side+"Foot",out var f))return;
            var a=u.bone;var b=k.bone;var c=f.bone;
            float upper=Vector3.Distance(a.position,b.position),lower=Vector3.Distance(b.position,c.position);
            var ray=target-a.position;float distance=ray.magnitude;if(upper<.001f || lower<.001f || distance<.001f)return;
            var direction=ray/distance;var bend=Vector3.ProjectOnPlane(b.position-a.position,direction);
            if(bend.sqrMagnitude<1e-10f)bend=Vector3.ProjectOnPlane(actor.transform.forward,direction);
            if(bend.sqrMagnitude<1e-10f)return;
            distance=Mathf.Clamp(distance,Mathf.Abs(upper-lower)+.000001f,upper+lower-.000001f);
            float along=(upper*upper+distance*distance-lower*lower)/(2*distance);
            var knee=a.position+direction*along+bend.normalized*Mathf.Sqrt(Mathf.Max(0,upper*upper-along*along));
            a.rotation=Quaternion.FromToRotation(b.position-a.position,knee-a.position)*a.rotation;
            b.rotation=Quaternion.FromToRotation(c.position-b.position,target-b.position)*b.rotation;
            c.rotation=footRotation;
        }
    }
}
