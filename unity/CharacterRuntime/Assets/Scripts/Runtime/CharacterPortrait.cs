using UnityEngine;

namespace ModelSpace
{
    // Baked from the neutral rig, never from an animated frame. Eye spacing gives
    // a face-sized reference even when ears, tails or hats inflate total height.
    [System.Serializable] public sealed class CharacterPortrait
    {
        public int version=1;
        public Vector3 localFace;
        public float localFaceHeight;
        public Bounds localRegion;
        public string measurement;
        public Vector3 Face(Transform root)=>root.TransformPoint(localFace);
        public float FaceHeight(Transform root)=>root.TransformVector(Vector3.up*localFaceHeight).magnitude;
        public Bounds Region(Transform root)
        {
            var result=new Bounds(root.TransformPoint(localRegion.center),Vector3.zero);
            for(int i=0;i<8;i++)result.Encapsulate(root.TransformPoint(FramingMath.Corner(localRegion,i)));
            return result;
        }
        public void Compose(Transform root,Quaternion rotation,float aspect,float fov,float size,float near,
            out Vector3 focus,out float distance)
            =>ComposeAt(Face(root),FaceHeight(root),rotation,aspect,fov,size,near,out focus,out distance);
        public static void ComposeAt(Vector3 face,float faceHeight,Quaternion rotation,float aspect,float fov,float size,float near,
            out Vector3 focus,out float distance)
        {
            float tangent=Mathf.Tan(fov*Mathf.Deg2Rad*.5f);
            // Aim for an intimate upper-body view on narrow phones;
            // wide windows retain a less aggressive framing. Final hardware-safe
            // constraints may retreat for unusually large ears/headwear.
            float fraction=Mathf.Lerp(.34f,.40f,Mathf.InverseLerp(.6f,1.8f,aspect));
            distance=Mathf.Max(near*3,faceHeight/(2*tangent*fraction*FramingMath.Size(size)));
            focus=face-rotation*Vector3.up*(distance*2*tangent*.18f);
        }
    }
}
