using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace ModelSpace
{
    [Serializable] public sealed class CharacterAtmosphere {public string id,title,background,effect,backgroundSHA256,imageModel;public string[] palette;public float density=.7f;}
    [Serializable] public sealed class CharacterAtmosphereCatalog {public int schemaVersion;public CharacterAtmosphere[] characters;}
    /// One camera-space image, not a new world/room. Small depth-weighted UV
    /// parallax gives the authored image life without moving the avatar camera.
    public sealed class CharacterImageBackdrop:MonoBehaviour
    {
        public const int Revision=1;
        Camera view;Material material;Mesh mesh;MeshRenderer renderer;
        CharacterAtmosphereCatalog catalog;
        public CharacterAtmosphere Current {get;private set;}
        public bool Visible=>renderer && renderer.enabled;
        public bool Bind(Camera camera,string role)
        {
            view=camera;
            if(catalog==null) {var data=Resources.Load<TextAsset>("CharacterAtmospheres");if(data) catalog=JsonUtility.FromJson<CharacterAtmosphereCatalog>(data.text);}
            Current=catalog?.schemaVersion==1 ? Array.Find(catalog.characters,c=>c.id==role) : null;
            var texture=Current==null ? null : Resources.Load<Texture2D>(Current.background);
            if(!texture) {if(renderer) renderer.enabled=false;return false;}
            if(!renderer)
            {
                var shader=Resources.Load<Shader>("AtmosphereBackdrop");if(!shader) throw new InvalidOperationException("ATMOSPHERE_SHADER_MISSING");
                material=new Material(shader);
                var root=new GameObject("CharacterImageBackdrop");root.transform.SetParent(transform,false);
                mesh=new Mesh {name="Backdrop quad"};mesh.vertices=new[]{new Vector3(-1,-1,0),new Vector3(1,-1,0),new Vector3(-1,1,0),new Vector3(1,1,0)};
                mesh.uv=new[]{Vector2.zero,Vector2.right,Vector2.up,Vector2.one};mesh.triangles=new[]{0,2,1,2,3,1};mesh.bounds=new Bounds(Vector3.zero,Vector3.one*10000);
                root.AddComponent<MeshFilter>().sharedMesh=mesh;renderer=root.AddComponent<MeshRenderer>();renderer.sharedMaterial=material;
                renderer.shadowCastingMode=ShadowCastingMode.Off;renderer.receiveShadows=false;
                renderer.lightProbeUsage=LightProbeUsage.Off;renderer.reflectionProbeUsage=ReflectionProbeUsage.Off;
            }
            material.mainTexture=texture;renderer.enabled=true;LateUpdate();return true;
        }
        void LateUpdate()
        {
            if(!Visible || !view || !material.mainTexture) return;
            float aspect=view.aspect,imageAspect=(float)material.mainTexture.width/material.mainTexture.height;
            material.SetVector("_Crop",new Vector4(Mathf.Min(1,aspect/imageAspect)*.968f,Mathf.Min(1,imageAspect/aspect)*.968f,0,0));
            // Approx. one screen pixel of slow drift; foreground layers provide
            // stronger depth. Camera gestures never rotate the painted room.
            material.SetVector("_Drift",new Vector4(Mathf.Sin(Time.unscaledTime*.09f)*.0015f,Mathf.Cos(Time.unscaledTime*.07f)*.001f,0,0));
        }
        void OnDestroy(){if(material) Destroy(material);if(mesh) Destroy(mesh);}
    }
}
