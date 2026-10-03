using System;
using System.IO;
using System.IO.Compression;
using System.Text;

public static class CharacterMotionData
{
    // Compressed storage is explicit in core.source-motions@1; older packages
    // retain their original JSON format. Bound expanded data before parsing.
    public static string Read(string jsonPath)
    {
        if(!File.Exists(jsonPath+".gz"))return File.ReadAllText(jsonPath);
        using(var file=File.OpenRead(jsonPath+".gz"))using(var zip=new GZipStream(file,CompressionMode.Decompress))using(var memory=new MemoryStream()){
            var buffer=new byte[65536];int count;
            while((count=zip.Read(buffer,0,buffer.Length))>0){if(memory.Length+count>128*1024*1024)throw new Exception("MOTION_DATA_EXPANDED_BUDGET");memory.Write(buffer,0,count);}
            return Encoding.UTF8.GetString(memory.ToArray());
        }
    }
}
