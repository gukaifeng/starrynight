using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;

// Import-time subset of PMX 2.0/2.1. No MMD interpreter or physics library ships in the App.
internal sealed class PmxModelData
{
    internal sealed class Surface { public string name, texture; public Color color; public int flags, start, count; }
    internal sealed class Bone { public string name; public int parent; public Vector3 position; }
    internal sealed class Morph { public string name; public Dictionary<int,Vector3> offsets = new(); }
    public Vector3[] vertices, normals;
    public Vector2[] uv;
    public BoneWeight[] weights;
    public int[] indices;
    public Surface[] surfaces;
    public Bone[] bones;
    public readonly List<Morph> morphs = new();
    public int sdefVertices;
    BinaryReader reader;
    byte[] header;
    const float Scale = .28f;
    Vector3 Vector() => new(-reader.ReadSingle()*Scale,reader.ReadSingle()*Scale,-reader.ReadSingle()*Scale);
    void Skip(int count) => reader.BaseStream.Seek(count,SeekOrigin.Current);
    string Text()
    {
        int size=reader.ReadInt32();
        if(size<0||size>reader.BaseStream.Length-reader.BaseStream.Position)throw new InvalidDataException("PMX text length");
        return (header[0]==0?Encoding.Unicode:Encoding.UTF8).GetString(reader.ReadBytes(size));
    }
    int Index(int slot,bool unsigned=false) => header[slot] switch {
        1=>unsigned?reader.ReadByte():reader.ReadSByte(),
        2=>unsigned?reader.ReadUInt16():reader.ReadInt16(),
        4=>reader.ReadInt32(),_=>throw new InvalidDataException("PMX index size")};
    public static PmxModelData Load(string path)
    {
        var data=new PmxModelData();
        using var file=File.OpenRead(path);using var r=new BinaryReader(file);data.reader=r;data.Read();return data;
    }
    void Read()
    {
        if(Encoding.ASCII.GetString(reader.ReadBytes(4))!="PMX ")throw new InvalidDataException("PMX signature");
        float version=reader.ReadSingle();if(version<2||version>2.1f)throw new InvalidDataException("PMX version");
        header=reader.ReadBytes(reader.ReadByte());if(header.Length<8)throw new InvalidDataException("PMX header");
        for(int i=0;i<4;i++)Text();
        int count=reader.ReadInt32();if(count<1||count>1000000)throw new InvalidDataException("PMX vertex count");
        vertices=new Vector3[count];normals=new Vector3[count];uv=new Vector2[count];weights=new BoneWeight[count];
        for(int i=0;i<count;i++)
        {
            vertices[i]=Vector();normals[i]=Vector().normalized;
            uv[i]=new Vector2(reader.ReadSingle(),1-reader.ReadSingle());Skip(header[1]*16);
            int type=reader.ReadByte();var w=new BoneWeight();
            w.boneIndex0=Math.Max(0,Index(5));
            if(type==0)w.weight0=1;
            else if(type==1||type==3)
            {
                w.boneIndex1=Math.Max(0,Index(5));w.weight0=reader.ReadSingle();w.weight1=1-w.weight0;
                // Unity's four-influence skinning: SDEF is converted to linear two-bone skinning.
                if(type==3){Skip(36);sdefVertices++;}
            }
            else if(type==2||type==4)
            {
                w.boneIndex1=Math.Max(0,Index(5));w.boneIndex2=Math.Max(0,Index(5));w.boneIndex3=Math.Max(0,Index(5));
                w.weight0=reader.ReadSingle();w.weight1=reader.ReadSingle();w.weight2=reader.ReadSingle();w.weight3=reader.ReadSingle();
            }
            else throw new InvalidDataException("Unsupported PMX weight type");
            weights[i]=w;Skip(4);
        }
        indices=new int[reader.ReadInt32()];for(int i=0;i<indices.Length;i++)indices[i]=Index(2,true);
        var textures=new string[reader.ReadInt32()];for(int i=0;i<textures.Length;i++)textures[i]=Text().Replace('\\','/');
        surfaces=new Surface[reader.ReadInt32()];int start=0;
        for(int i=0;i<surfaces.Length;i++)
        {
            var s=new Surface{name=Text()};Text();s.color=new Color(reader.ReadSingle(),reader.ReadSingle(),reader.ReadSingle(),reader.ReadSingle());
            Skip(28);s.flags=reader.ReadByte();Skip(20);int tex=Index(3);s.texture=tex>=0?textures[tex]:null;
            Index(3);Skip(1);int toon=reader.ReadByte();Skip(toon==0?header[3]:1);Text();
            s.start=start;s.count=reader.ReadInt32();start+=s.count;surfaces[i]=s;
        }
        if(start!=indices.Length)throw new InvalidDataException("PMX surface index count");
        bones=new Bone[reader.ReadInt32()];
        for(int i=0;i<bones.Length;i++)
        {
            var b=new Bone{name=Text()};Text();b.position=Vector();b.parent=Index(5);Skip(4);
            int flags=reader.ReadUInt16();Skip((flags&1)!=0?header[5]:12);
            if((flags&0x300)!=0)Skip(header[5]+4);
            if((flags&0x400)!=0)Skip(12);
            if((flags&0x800)!=0)Skip(24);
            if((flags&0x2000)!=0)Skip(4);
            if((flags&0x20)!=0)
            {
                Skip(header[5]+8);int links=reader.ReadInt32();
                for(int j=0;j<links;j++){Skip(header[5]);if(reader.ReadByte()!=0)Skip(24);}
            }
            bones[i]=b;
        }
        int morphCount=reader.ReadInt32();
        for(int i=0;i<morphCount;i++)
        {
            var m=new Morph{name=Text()};Text();Skip(1);int type=reader.ReadByte(),n=reader.ReadInt32();
            for(int j=0;j<n;j++)
            {
                switch(type)
                {
                    case 1:m.offsets[Index(2,true)]=Vector();break;
                    case 0:case 9:Skip(header[6]+4);break;
                    case 2:Skip(header[5]+28);break;
                    case 3:case 4:case 5:case 6:case 7:Skip(header[2]+16);break;
                    case 8:Skip(header[4]+113);break;
                    case 10:Skip(header[7]+25);break;
                    default:throw new InvalidDataException("Unsupported PMX morph type");
                }
            }
            if(type==1)morphs.Add(m);
        }
    }
}
