using System;
using ModelSpace;
using UnityEngine;

// Runs the real runtime class against Unity's managed mathematics, without a
// scene, renderer, model assets or any AI/API calls. This is not a UIKit test.
public static class CharacterPreviewRotationTests
{
    static int checks;
    static void Check(bool condition,string message)
    {
        checks++;if(!condition)throw new Exception(message);
    }
    static void Tick(CharacterPreviewRotation rotation,int hz,int frames)
    {
        for(int i=0;i<frames;i++) {
            rotation.Step(1f/hz);
            Check(float.IsFinite(rotation.Offset.x) && float.IsFinite(rotation.Offset.y),"finite output");
            Check(Math.Abs(rotation.Offset.x)<=18.0001f && Math.Abs(rotation.Offset.y)<=8.0001f,"hard small-angle envelope");
        }
    }
    public static void Main()
    {
        foreach(int hz in new[]{30,60,120}) {
            var rotation=new CharacterPreviewRotation();
            rotation.Begin();rotation.Move(4,-4);Tick(rotation,hz,hz);
            Check(rotation.Offset.x<-17.9f && rotation.Offset.y>7.9f,"visible, bounded response");
            rotation.Move(-4,4);Tick(rotation,hz,hz);
            Check(rotation.Offset.x>17.9f && rotation.Offset.y<-7.9f,"both directions");
            var before=rotation.Offset;
            rotation.Move(float.NaN,1);rotation.Move(1,float.PositiveInfinity);
            rotation.Step(float.NaN);rotation.Step(float.PositiveInfinity);rotation.Step(-1);
            Check(rotation.Offset==before,"reject invalid input and frame time");
            rotation.End();Check(!rotation.Active && rotation.Offset==before,"release does not snap");
            Tick(rotation,hz,Math.Max(1,hz/10));
            Check(rotation.Offset.sqrMagnitude<before.sqrMagnitude && rotation.Offset.sqrMagnitude>0,"smooth return in progress");
            var regrab=rotation.Offset;
            rotation.Begin();rotation.Move(0,0);rotation.Step(1f/hz);
            Check(Vector2.Distance(regrab,rotation.Offset)<2,"regrab during return stays continuous");
            rotation.Move(1,1);Tick(rotation,hz,hz/2);rotation.End();
            Tick(rotation,hz,hz*2);
            Check(rotation.Offset==Vector2.zero && rotation.ReturnCount==1,"release/cancel returns exactly, once");
            Check(rotation.Count==2,"drag count");
            rotation.Begin();rotation.Move(-1,-1);Tick(rotation,hz,hz/2);
            rotation.Reset();Check(rotation.Offset==Vector2.zero && !rotation.Active && rotation.Count==0,"new actor clears transient state");
        }
        // Same physical duration must have similar motion on 60/120 Hz displays.
        var a=new CharacterPreviewRotation();var b=new CharacterPreviewRotation();
        a.Begin();b.Begin();a.Move(.15f,.12f);b.Move(.15f,.12f);
        Tick(a,60,6);Tick(b,120,12);
        Check(Vector2.Distance(a.Offset,b.Offset)<.12f,"refresh-rate-independent response");
        Console.WriteLine("CHARACTER_PREVIEW_ROTATION_PASS checks="+checks+" rates=30,60,120");
    }
}
