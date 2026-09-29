using System;
using System.Collections.Generic;
using System.IO;
using ModelSpace;
using UnityEngine;

public static class FramingMotionReview
{
    [Serializable] class Sample { public float time, progress, velocity; }
    [Serializable] class Curve { public string direction; public float response, maximumProgress; public Sample[] samples; }
    [Serializable] class Report { public int revision = CameraFramingMotion.Revision; public string result = "passed"; public Curve[] curves; }
    static void Require(bool condition, string message) { if (!condition) throw new Exception("Framing motion: " + message); }
    public static void Validate()
    {
        ValidateComposition();
        ValidateGroundedComposition();
        var curves = new List<Curve>();
        foreach (float response in new[] { CameraFramingMotion.ActionResponse, CameraFramingMotion.ReturnResponse, CameraFramingMotion.LayoutResponse })
        {
            var motion = new CameraFramingMotion();
            motion.SetTarget(Vector3.zero, 1); motion.SetTarget(Vector3.up, 2);
            var samples = new List<Sample>();
            float maximum = 0, initialSpeed = 0, peakSpeed = 0;
            bool layout = response == CameraFramingMotion.LayoutResponse;
            for (int frame = 0; frame <= (layout ? 600 : 240); ++frame)
            {
                float progress = Mathf.Log(motion.Distance) / Mathf.Log(2);
                maximum = Mathf.Max(maximum, progress); peakSpeed = Mathf.Max(peakSpeed, motion.ZoomVelocity);
                samples.Add(new Sample { time = frame/120f, progress = progress, velocity = motion.ZoomVelocity });
                if (frame == 2) { Require(progress < .025f, "first frame must ease in"); initialSpeed = motion.ZoomVelocity; }
                if (layout && frame == 30) Require(progress > .2f && progress < .4f,"layout must remain gradual at 250 ms");
                if (layout && frame == 90) Require(progress > .85f && progress < 1,"layout needs a visible main travel before rebound");
                motion.Step(1f/120, response);
            }
            Require(maximum > 1.005f && maximum < (layout ? 1.035f : 1.025f), "one restrained overshoot");
            Require(peakSpeed > initialSpeed * 2, "gradual acceleration");
            Require(motion.Settled && Mathf.Abs(motion.Distance-2) < .001f, "must settle precisely");
            curves.Add(new Curve { direction = layout ? "layout" : response == CameraFramingMotion.ActionResponse ? "action" : "return",
                response = response, maximumProgress = maximum, samples = samples.ToArray() });
        }
        // Equivalent elapsed times at 30 / 60 / 120 Hz must produce the same pose.
        foreach (float scale in new[] { .1f, 1f, 20f })
        {
            var reference = Run(120, scale);
            foreach (int fps in new[] { 30, 60 })
            {
                var other = Run(fps, scale);
                Require(Mathf.Abs(other.Distance-reference.Distance) < scale*.00002f, "frame-rate independent distance");
                Require(Vector3.Distance(other.Focus,reference.Focus) < scale*.00002f, "frame-rate independent focus");
                Require(Mathf.Abs(other.Pitch-reference.Pitch) < .0001f,"frame-rate independent pitch");
            }
        }
        var interrupted = Run(120, 1);
        float before = interrupted.Distance, velocity = interrupted.ZoomVelocity;
        var focus = interrupted.Focus;
        interrupted.SetTarget(Vector3.down, .8f);
        Require(interrupted.Distance == before && interrupted.Focus == focus && interrupted.ZoomVelocity == velocity,
            "retarget must preserve position and velocity");
        interrupted.Step(0, CameraFramingMotion.ReturnResponse);
        Require(interrupted.Distance == before, "paused frame must not jump");
        interrupted.Step(3, CameraFramingMotion.ReturnResponse);
        Require(Mathf.Abs(Mathf.Log(interrupted.Distance/before)) < .2f, "resume must not consume a multi-second jump");
        for (int frame=0; frame<240; ++frame) interrupted.Step(1f/120, CameraFramingMotion.ReturnResponse);
        Require(interrupted.Settled && Mathf.Abs(interrupted.Distance-.8f)<.001f, "interrupted recovery");
        interrupted.SetTarget(Vector3.one, 3); interrupted.Snap();
        Require(interrupted.Settled && interrupted.ZoomVelocity == 0 && Mathf.Abs(interrupted.Distance-3)<.00001f,
            "selecting a new model must not inherit previous momentum");
        string folder = Path.GetFullPath("../../.local/checks/framing-motion"); Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder,"spring-curves.json"),JsonUtility.ToJson(new Report { curves = curves.ToArray() },true));
        Debug.Log("Framing motion validation passed: easing, bounded overshoot, 30/60/120 Hz, rig scale, interruption and resume.");
    }
    static void ValidateComposition()
    {
        // The solved full-screen camera must contain all eight projected corners inside the
        // intended preview, including extreme aspect ratios, depth and off-centre composition.
        foreach (float aspect in new[] { .46f,.7f,1.4f,2.16f })
        foreach (float scale in new[] { .1f,1f,20f })
        foreach (float angle in new[] { -20f,0f,20f })
        foreach (Rect area in new[] { new Rect(0,0,1,1),new Rect(0,.48f,1,.34f),new Rect(.08f,.55f,.56f,.26f) })
        {
            var region = new Bounds(Vector3.up*scale,new Vector3(.9f,1.4f,.6f)*scale);
            var rotation = FramingMath.Rotation(angle);
            FramingMath.Compose(region,rotation,aspect,35,1.1f,.01f,area,out var focus,out var distance);
            var position = focus-rotation*Vector3.forward*distance;
            for (int corner=0; corner<8; ++corner)
            {
                var point = region.center+Vector3.Scale(region.extents,new Vector3((corner&1)==0 ? -1:1,(corner&2)==0 ? -1:1,(corner&4)==0 ? -1:1));
                point = Quaternion.Inverse(rotation)*(point-position);
                float tangent = Mathf.Tan(35*Mathf.Deg2Rad*.5f);
                var uv = new Vector2(.5f+point.x/(2*point.z*tangent*aspect),.5f+point.y/(2*point.z*tangent));
                Require(area.Contains(uv),"composition must fit every corner");
            }
            var motion = new CameraFramingMotion(); motion.SetTarget(region.center,scale*2);
            var start = motion.Focus; float oldDistance = motion.Distance;
            motion.SetTarget(focus,distance);
            Require(motion.Focus == start && motion.Distance == oldDistance,"UI target must not teleport camera");
            for (int frame=0;frame<600;frame++) motion.Step(1f/120,CameraFramingMotion.LayoutResponse);
            Require(motion.Settled,"UI composition must settle");
        }
        Debug.Log("Layout composition validation passed: 108 off-centre/aspect/scale cases, full-screen projection, continuous retarget.");
    }
    static CameraFramingMotion Run(int fps, float scale)
    {
        var motion = new CameraFramingMotion(); motion.SetTarget(Vector3.zero,scale);
        motion.SetTarget(new Vector3(1,2,3)*scale,2*scale,14);
        for (int frame=0; frame<fps/3; ++frame) motion.Step(1f/fps,CameraFramingMotion.ActionResponse);
        return motion;
    }
    static void ValidateGroundedComposition()
    {
        int cases = 0;
        foreach (float aspect in new[] {.46f,1.4f,2.17f})
        foreach (float scale in new[] {.1f,1f,20f})
        foreach (float angle in new[] {-20f,0f,20f})
        foreach (float height in new[] {.45f,1.8f})
        {
            var region = new Bounds(Vector3.up*height*.5f*scale,new Vector3(1.8f,height,.6f)*scale);
            var motion = new CameraFramingMotion();
            foreach (Rect area in new[] {new Rect(.08f,.07f,.46f,.76f),new Rect(.08f,.63f,.46f,.20f),new Rect(.08f,.07f,.46f,.76f)})
            {
                float pitch = FramingMath.CompositionPitch(area,35);
                var rotation = Quaternion.Euler(pitch,FramingMath.FrontYaw+angle,0);
                FramingMath.Compose(region,rotation,aspect,35,1.1f,.01f,area,out var focus,out var distance);
                var position = focus-rotation*Vector3.forward*distance;
                Require(position.y > 0,"upper composition must not place camera below floor");
                for (int corner=0;corner<8;corner++)
                {
                    var point=region.center+Vector3.Scale(region.extents,new Vector3((corner&1)==0?-1:1,(corner&2)==0?-1:1,(corner&4)==0?-1:1));
                    point=Quaternion.Inverse(rotation)*(point-position);
                    float tangent=Mathf.Tan(35*Mathf.Deg2Rad*.5f);
                    Require(area.Contains(new Vector2(.5f+point.x/(2*point.z*tangent*aspect),.5f+point.y/(2*point.z*tangent))),"ground-safe pitch must still fit all corners");
                }
                float before=motion.Pitch;
                motion.SetTarget(focus,distance,pitch);
                if (cases>0 && !motion.Settled) Require(motion.Pitch==before,"pitch target must not snap");
                for (int frame=0;frame<600;frame++)
                {
                    motion.Step(1f/120,CameraFramingMotion.LayoutResponse);
                    var eye=motion.Focus-Quaternion.Euler(motion.Pitch,FramingMath.FrontYaw+angle,0)*Vector3.forward*motion.Distance;
                    Require(eye.y>0,"keyboard transition must keep camera above floor");
                }
                Require(motion.Settled,"pitch must settle with composition");
                cases++;
            }
        }
        Debug.Log("Ground-safe composition passed: "+cases+" cases, eight corners and 600 transition samples each.");
    }
}
