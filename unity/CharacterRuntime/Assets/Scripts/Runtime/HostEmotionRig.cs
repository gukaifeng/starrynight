using System;
using UnityEngine;

namespace ModelSpace
{
    // HOST-EMOTION-EXPERIMENT v2. Generated calibration, never part of the
    // author's XCP contract/controller. Removing the builder hook removes it.
    public sealed class HostEmotionRig : MonoBehaviour
    {
        [Serializable] public sealed class Joint
        {
            public string human;
            public Transform bone;
            public Quaternion axes;
            public Quaternion rest;
            public Vector3 elbowAxis;
            public float lateralSign=1;
        }
        public Joint[] joints=Array.Empty<Joint>();
        [Serializable] public sealed class Face
        {
            public string gesture,label;
            public SkinnedMeshRenderer[] skins=Array.Empty<SkinnedMeshRenderer>();
            public int[] indices=Array.Empty<int>();
            public float[] values=Array.Empty<float>();
        }
        public Face[] faces=Array.Empty<Face>();
        public Transform leftFoot,rightFoot,leftHand,rightHand;
        public string[] blockingParameters=Array.Empty<string>();
        public float amplitude=1;
    }
}
