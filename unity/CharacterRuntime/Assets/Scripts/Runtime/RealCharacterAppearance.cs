using UnityEngine;

namespace ModelSpace
{
    public sealed class RealCharacterAppearance : MonoBehaviour
    {
        public SkinnedMeshRenderer[] meshes;
        public GameObject longHair, bobHair;
        public Transform stature;
        MaterialPropertyBlock block;
        public void Configure(StudioSettings s)
        {
            block ??= new MaterialPropertyBlock();
            var channels = new[] { "FaceWidth", "JawShape", "EyeSize", "MouthShape", "NoseWidth", "BodyBuild", "BodyCurve" };
            var values = new[] { s.faceWidth, s.jawShape, s.eyeSize, s.mouthShape, s.noseWidth, s.bodyBuild, s.bodyCurve };
            foreach (var mesh in meshes)
            {
                for (int i = 0; i < channels.Length; i++)
                {
                    float v = (StudioSettings.Safe(values[i],0,1,.5f)-.5f)*2;
                    SetShape(mesh,channels[i]+"Plus",Mathf.Max(0,v)*100);
                    SetShape(mesh,channels[i]+"Minus",Mathf.Max(0,-v)*100);
                }
                for (int slot = 0; slot < mesh.sharedMaterials.Length; slot++)
                {
                    string material = mesh.sharedMaterials[slot].name;
                    mesh.GetPropertyBlock(block,slot);
                    if (material.StartsWith("RealSkin"))
                    {
                        Color color = s.skin == "fair" ? new Color(1.04f,1.02f,1)
                            : s.skin == "warm" ? new Color(.8f,.62f,.48f) : s.skin == "deep" ? new Color(.49f,.30f,.20f) : Color.white;
                        block.SetColor("_BaseColor",color);
                    }
                    else if (material.StartsWith("RealHair"))
                    {
                        Color color = s.hairColor == "black" ? new Color(.32f,.30f,.28f)
                            : s.hairColor == "chestnut" ? new Color(1,.72f,.50f) : new Color(.65f,.50f,.42f);
                        block.SetColor("_BaseColor",color);
                    }
                    else if (material.StartsWith("RealClothes"))
                        block.SetColor("_BaseColor",s.clothing == "sage" ? new Color(.64f,.79f,.67f)
                            : s.clothing == "rose" ? new Color(.86f,.61f,.58f) : Color.white);
                    else if (material.StartsWith("RealEyes"))
                        block.SetColor("_IrisTint",s.eyes == "green" ? new Color(.35f,.56f,.43f)
                            : s.eyes == "hazel" ? new Color(.65f,.44f,.21f) : new Color(.28f,.15f,.08f));
                    mesh.SetPropertyBlock(block,slot); block.Clear();
                }
            }
            if (longHair) longHair.SetActive(s.hair != "bob");
            if (bobHair) bobHair.SetActive(s.hair == "bob");
            if (stature) stature.localScale = Vector3.one * Mathf.Lerp(.94f,1.06f,StudioSettings.Safe(s.height,0,1,.5f));
        }
        static void SetShape(SkinnedMeshRenderer renderer,string name,float value)
        {
            int index = renderer.sharedMesh.GetBlendShapeIndex(name);
            if (index >= 0) renderer.SetBlendShapeWeight(index,value);
        }
    }
}
