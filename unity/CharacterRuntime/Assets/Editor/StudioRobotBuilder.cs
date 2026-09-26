using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

// Original, reproducible geometry. No downloaded model, texture or animation dependency.
public static class StudioRobotBuilder
{
    const string Folder = "Assets/StudioRobot";
    static readonly Dictionary<string, Material> materials = new();
    public static GameObject Create()
    {
        System.IO.Directory.CreateDirectory(Folder);
        materials.Clear();
        Material shell = Material("Porcelain", new Color(.92f,.90f,.84f), .08f, .42f);
        Material metal = Material("Titanium", new Color(.22f,.29f,.34f), .88f, .62f);
        Material dark = Material("Graphite", new Color(.025f,.045f,.062f), .45f, .42f);
        Material glass = Material("Visor", new Color(.012f,.031f,.043f), .62f, .9f);
        Material teal = Material("Enamel", new Color(.025f,.42f,.45f), .45f, .48f);
        Material eye = Material("Light", new Color(.36f,.94f,1), .1f, .4f);
        eye.EnableKeyword("_EMISSION"); eye.SetColor("_EmissionColor", new Color(.2f,.85f,1)*1.3f);
        var root = new GameObject("DefaultCharacter");
        Transform rig = Pivot("Rig", root.transform, Vector3.zero);
        Transform body = Pivot("Body", rig, new Vector3(0,2.05f,0));
        Box("Torso",body,Vector3.zero,new Vector3(1.35f,1.35f,.86f),.28f,shell);
        Box("ChestInset",body,new Vector3(0,.06f,.422f),new Vector3(.67f,.63f,.065f),.15f,metal);
        Box("ChestPanel",body,new Vector3(0,.07f,.46f),new Vector3(.56f,.52f,.04f),.12f,teal);
        Box("Status",body,new Vector3(0,.1f,.487f),new Vector3(.24f,.052f,.025f),.018f,eye);
        Box("Waist",rig,new Vector3(0,1.32f,0),new Vector3(.86f,.22f,.62f),.1f,dark);
        Box("Neck",body,new Vector3(0,.79f,0),new Vector3(.46f,.27f,.43f),.1f,metal);
        Transform head = Pivot("HeadPivot", body, new Vector3(0,1.35f,0));
        Box("Head",head,Vector3.zero,new Vector3(1.88f,1.23f,1.12f),.3f,shell);
        Box("VisorRim",head,new Vector3(0,.01f,.50f),new Vector3(1.64f,.9f,.2f),.24f,metal);
        Box("Face",head,new Vector3(0,.015f,.586f),new Vector3(1.52f,.77f,.13f),.23f,glass);
        for (int side=-1;side<=1;side+=2)
        {
            Box("Eye"+side,head,new Vector3(side*.34f,.055f,.658f),new Vector3(.16f,.28f,.028f),.07f,eye);
            Box("Ear"+side,head,new Vector3(side*.963f,0,0),new Vector3(.16f,.51f,.52f),.075f,metal);
            Box("EarInlay"+side,head,new Vector3(side*1.049f,0,0),new Vector3(.02f,.25f,.27f),.009f,teal);
            string suffix = side < 0 ? "Left" : "Right";
            Transform arm = Pivot("Arm"+suffix,body,new Vector3(side*.86f,.43f,0));
            Box("Shoulder"+suffix,arm,Vector3.zero,new Vector3(.44f,.46f,.54f),.2f,metal);
            Box("Sleeve"+suffix,arm,new Vector3(0,-.37f,0),new Vector3(.44f,.53f,.47f),.17f,shell);
            Transform forearm = Pivot("Forearm"+suffix,arm,new Vector3(0,-.7f,0));
            Box("Elbow"+suffix,forearm,Vector3.zero,new Vector3(.29f,.27f,.32f),.13f,dark);
            Box("Hand"+suffix,forearm,new Vector3(0,-.32f,.018f),new Vector3(.46f,.51f,.48f),.2f,shell);
            Box("Cuff"+suffix,forearm,new Vector3(0,-.12f,.022f),new Vector3(.465f,.12f,.485f),.055f,teal);
            Transform leg = Pivot("Leg"+suffix,rig,new Vector3(side*.39f,1.15f,0));
            Box("Hip"+suffix,leg,Vector3.zero,new Vector3(.39f,.28f,.45f),.12f,metal);
            Box("Shin"+suffix,leg,new Vector3(0,-.37f,0),new Vector3(.52f,.65f,.57f),.19f,shell);
            Box("Ankle"+suffix,leg,new Vector3(0,-.76f,0),new Vector3(.35f,.22f,.4f),.09f,dark);
            Box("Foot"+suffix,leg,new Vector3(0,-.96f,.13f),new Vector3(.63f,.35f,.92f),.16f,shell);
            Box("Sole"+suffix,leg,new Vector3(0,-1.105f,.13f),new Vector3(.63f,.08f,.92f),.035f,metal);
        }
        var player = root.AddComponent<Animation>();
        foreach (string name in new[]{"Idle","Wave","Jump","Dance","No"})
        {
            var clip = Clip(name);
            Save(clip, Folder+"/"+name+".anim");
            player.AddClip(AssetDatabase.LoadAssetAtPath<AnimationClip>(Folder+"/"+name+".anim"),name);
        }
        player.clip = player.GetClip("Idle"); player.playAutomatically=false; player.enabled=false;
        return root;
    }
    static AnimationClip Clip(string name)
    {
        float duration = name switch { "Wave"=>1.8333f,"Jump"=>.9f,"Dance"=>3.3333f,"No"=>1.6667f,_=>3.3333f };
        var clip = new AnimationClip { name=name,legacy=true,frameRate=120,wrapMode=name=="Idle"?WrapMode.Loop:WrapMode.Once };
        // Continuous curves are evaluated at every rendered frame, not stepped at authored FPS.
        foreach (string path in new[]{"Rig","Rig/Body","Rig/Body/HeadPivot","Rig/Body/ArmLeft","Rig/Body/ArmRight",
            "Rig/Body/ArmLeft/ForearmLeft","Rig/Body/ArmRight/ForearmRight","Rig/LegLeft","Rig/LegRight"})
        for(int axis=0;axis<3;axis++)
        {
            int a=axis; string p=path;
            Curve(clip,path,"localEulerAnglesRaw."+"xyz"[axis],duration,t=>Rotation(name,p,a,t,duration));
        }
        Curve(clip,"Rig","localPosition.y",duration,t=>name=="Jump" ? .95f*Mathf.Pow(Mathf.Sin(Mathf.PI*t/duration),2) :
            name=="Dance" ? .055f*(1-Mathf.Cos(t*2*Mathf.PI*2.4f))*Mathf.Sin(Mathf.PI*t/duration) : 0);
        return clip;
    }
    static float Rotation(string name,string path,int axis,float t,float duration)
    {
        float envelope = Mathf.Pow(Mathf.Max(0,Mathf.Sin(Mathf.PI*t/duration)),.8f);
        if (name=="Wave" && path=="Rig/Body/ArmRight" && axis==2) return 145*envelope;
        if (name=="Wave" && path=="Rig/Body/ArmRight/ForearmRight" && axis==2) return Mathf.Sin(t*17)*22*envelope;
        if (name=="No" && path=="Rig/Body/HeadPivot" && axis==1) return Mathf.Sin(t*12)*26*envelope;
        if (name=="Jump" && path.Contains("Arm") && !path.Contains("Forearm") && axis==2) return (path.EndsWith("Right")?1:-1)*55*envelope;
        if (name=="Dance")
        {
            if (path=="Rig/Body" && axis==2) return Mathf.Sin(t*8)*12*envelope;
            if (path=="Rig/Body/HeadPivot" && axis==1) return Mathf.Sin(t*8)*16*envelope;
            if (path.EndsWith("ArmLeft") && axis==2) return -35*envelope+Mathf.Sin(t*8)*25*envelope;
            if (path.EndsWith("ArmRight") && axis==2) return 35*envelope+Mathf.Sin(t*8)*25*envelope;
        }
        if (name=="Idle" && path=="Rig/Body/HeadPivot" && axis==2) return Mathf.Sin(t/duration*2*Mathf.PI)*1.2f;
        return 0;
    }
    static void Curve(AnimationClip clip,string path,string property,float length,Func<float,float> value)
    {
        const int samples=120;
        var keys=new Keyframe[samples+1];
        for(int i=0;i<=samples;i++){float t=length*i/samples;keys[i]=new Keyframe(t,value(t));}
        var curve=new AnimationCurve(keys);
        for(int i=0;i<=samples;i++) curve.SmoothTangents(i,0);
        clip.SetCurve(path,typeof(Transform),property,curve);
    }
    static Transform Pivot(string name,Transform parent,Vector3 position)
    { var go=new GameObject(name);go.transform.SetParent(parent,false);go.transform.localPosition=position;return go.transform; }
    static Material Material(string name,Color color,float metal,float smooth)
    {
        var m=AssetDatabase.LoadAssetAtPath<Material>(Folder+"/"+name+".mat");
        if(!m){m=new Material(Shader.Find("Universal Render Pipeline/Lit"));AssetDatabase.CreateAsset(m,Folder+"/"+name+".mat");}
        m.SetColor("_BaseColor",color);m.SetFloat("_Metallic",metal);m.SetFloat("_Smoothness",smooth);
        m.SetFloat("_Cull",2);
        EditorUtility.SetDirty(m);materials[name]=m;return m;
    }
    static void Box(string name,Transform parent,Vector3 position,Vector3 size,float radius,Material material)
    {
        var part=Pivot(name,parent,position);
        var mesh=RoundedBox(size,radius);mesh.name=name;
        string path=Folder+"/"+name+".asset";Save(mesh,path);
        part.gameObject.AddComponent<MeshFilter>().sharedMesh=AssetDatabase.LoadAssetAtPath<Mesh>(path);
        part.gameObject.AddComponent<MeshRenderer>().sharedMaterial=material;
    }
    static Mesh RoundedBox(Vector3 size,float radius)
    {
        var vertices=new List<Vector3>();var normals=new List<Vector3>();var uv=new List<Vector2>();var indices=new List<int>();
        Vector3 half=size*.5f;
        Vector3 radii=new Vector3(Mathf.Min(radius,half.x),Mathf.Min(radius,half.y),Mathf.Min(radius,half.z));
        Vector3 inner=half-radii;
        Vector3[] normalsFace={Vector3.right,Vector3.left,Vector3.up,Vector3.down,Vector3.forward,Vector3.back};
        foreach(var normal in normalsFace)
        {
            Vector3 u=Mathf.Abs(normal.y)>.5f?Vector3.right:Vector3.up, v=Vector3.Cross(normal,u);
            float hu=Vector3.Dot(half,new Vector3(Mathf.Abs(u.x),Mathf.Abs(u.y),Mathf.Abs(u.z)));
            float hv=Vector3.Dot(half,new Vector3(Mathf.Abs(v.x),Mathf.Abs(v.y),Mathf.Abs(v.z)));
            float hn=Vector3.Dot(half,new Vector3(Mathf.Abs(normal.x),Mathf.Abs(normal.y),Mathf.Abs(normal.z)));
            float[] xs=Coordinates(hu,Mathf.Min(radius,hu)),ys=Coordinates(hv,Mathf.Min(radius,hv));int start=vertices.Count,n=xs.Length;
            for(int y=0;y<n;y++)for(int x=0;x<n;x++)
            {
                Vector3 p=normal*hn+u*xs[x]+v*ys[y];
                Vector3 c=new Vector3(Mathf.Clamp(p.x,-inner.x,inner.x),Mathf.Clamp(p.y,-inner.y,inner.y),Mathf.Clamp(p.z,-inner.z,inner.z));
                Vector3 offset=p-c;
                Vector3 direction=new Vector3(offset.x/radii.x,offset.y/radii.y,offset.z/radii.z).normalized;
                vertices.Add(c+Vector3.Scale(direction,radii));
                normals.Add(new Vector3(direction.x/radii.x,direction.y/radii.y,direction.z/radii.z).normalized);
                uv.Add(new Vector2((float)x/(n-1),(float)y/(n-1)));
                if(x<n-1&&y<n-1){int a=start+y*n+x;indices.AddRange(new[]{a,a+1,a+n,a+1,a+n+1,a+n});}
            }
        }
        var mesh=new Mesh();mesh.SetVertices(vertices);mesh.SetNormals(normals);mesh.SetUVs(0,uv);mesh.SetTriangles(indices,0);mesh.RecalculateBounds();return mesh;
    }
    static float[] Coordinates(float half,float radius)
    {
        const int segments=6;var values=new float[2*(segments+1)];
        for(int i=0;i<=segments;i++){values[i]=-half+radius*i/segments;values[values.Length-1-i]=half-radius*i/segments;}return values;
    }
    static void Save(UnityEngine.Object asset,string path)
    {
        var existing=AssetDatabase.LoadMainAssetAtPath(path);
        if(existing)
        {
            // CopySerialized updates CPU mesh data but can leave the live GPU buffer stale.
            if(existing is Mesh target && asset is Mesh source)
            { target.Clear();target.vertices=source.vertices;target.normals=source.normals;target.uv=source.uv;target.triangles=source.triangles;target.RecalculateBounds(); }
            else if(existing is Cubemap oldCube && asset is Cubemap newCube)
            { for(int f=0;f<6;f++)oldCube.SetPixels(newCube.GetPixels((CubemapFace)f),(CubemapFace)f);oldCube.Apply(true); }
            else EditorUtility.CopySerialized(asset,existing);
            UnityEngine.Object.DestroyImmediate(asset);EditorUtility.SetDirty(existing);
        }
        else AssetDatabase.CreateAsset(asset,path);
    }
    public static Cubemap StudioReflection()
    {
        var cube=new Cubemap(128,TextureFormat.RGBAHalf,true);
        for(int face=0;face<6;face++)
        {
            var pixels=new Color[128*128];
            for(int y=0;y<128;y++)for(int x=0;x<128;x++)
            {
                float u=2*(x+.5f)/128-1,v=2*(y+.5f)/128-1;
                Vector3 d=face switch{0=>new Vector3(1,-v,-u),1=>new Vector3(-1,-v,u),2=>new Vector3(u,1,v),3=>new Vector3(u,-1,-v),4=>new Vector3(u,-v,1),_=>new Vector3(-u,-v,-1)};d.Normalize();
                Color c=Color.Lerp(new Color(.045f,.06f,.08f),new Color(.55f,.64f,.7f),Mathf.Clamp01(d.y*.6f+.4f));
                float box=Mathf.Pow(Mathf.Max(0,Vector3.Dot(d,new Vector3(-.5f,.7f,.5f).normalized)),48);
                float strip=Mathf.Pow(Mathf.Max(0,Vector3.Dot(d,new Vector3(.8f,.3f,-.4f).normalized)),80);
                pixels[y*128+x]=c+new Color(1,.92f,.8f)*box*4+new Color(.6f,.85f,1)*strip*3;
            }
            cube.SetPixels(pixels,(CubemapFace)face);
        }
        cube.Apply(true);Save(cube,Folder+"/StudioReflection.asset");return AssetDatabase.LoadAssetAtPath<Cubemap>(Folder+"/StudioReflection.asset");
    }
}
