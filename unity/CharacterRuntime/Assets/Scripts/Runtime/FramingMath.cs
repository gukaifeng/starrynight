using UnityEngine;

namespace ModelSpace
{
    // Conversation framing is deliberately bounded. UI values are validated again here.
    public static class FramingMath
    {
        public const float FrontYaw = 180, Pitch = 4, MinSize = .9f, MaxSize = 1.1f, MaxAngle = 20;
        public static float Size(float value) => float.IsNaN(value) || float.IsInfinity(value) ? 1 : Mathf.Clamp(value, MinSize, MaxSize);
        public static float Angle(float value) => float.IsNaN(value) || float.IsInfinity(value) ? 0 : Mathf.Clamp(value, -MaxAngle, MaxAngle);
        public static string Shot(string value) => value == "full" ? "full" : "conversation";
        public static Bounds Region(Bounds rest, string shot, bool action, float conversationStart = .42f)
        {
            float height = rest.size.y;
            Vector3 min = rest.min, max = rest.max;
            if (shot == "full")
            {
                min.y -= height * .025f;
                max.y += height * (action ? .32f : .065f);
                min.x -= rest.size.x * .08f; max.x += rest.size.x * .08f;
            }
            else
            {
                // An intimate waist-up composition. Hair tips and the relaxed hands may
                // leave the portrait; explicit full-body actions still use their baked envelope.
                min.y += height * Mathf.Clamp(conversationStart,.62f,.7f);
                max.y += height * .035f;
                float inset = rest.size.x * .22f;
                min.x += inset; max.x -= inset;
            }
            var region = new Bounds(); region.SetMinMax(min, max); return region;
        }
        public static Bounds FullRegion(Bounds envelope)
        {
            // Baked motion already includes the jump / arms. This margin covers sampling
            // intervals and subtle secondary motion; the frustum adds a further 18% reserve.
            envelope.Expand(envelope.size * .10f);
            return envelope;
        }
        public static Quaternion Rotation(float angle) => Quaternion.Euler(Pitch, FrontYaw + Angle(angle), 0);
        public static Vector3 ImmersiveFocus(Bounds region, Bounds rest, float conversationStart, Quaternion rotation,
            float aspect, float fov, float distance)
        {
            float lift = Mathf.Lerp(.19f,.015f,Mathf.InverseLerp(.5f,1.4f,aspect));
            float conversationHeight = Region(rest,"conversation",false,conversationStart).size.y;
            float closeup = Mathf.InverseLerp(rest.size.y,conversationHeight,region.size.y);
            float span = 2*distance*Mathf.Tan(fov*Mathf.Deg2Rad*.5f);
            return region.center-rotation*Vector3.up*(span*lift*closeup);
        }
        public static Rect SafeFrame(float x, float y, float width, float height)
        {
            if (!float.IsFinite(x) || !float.IsFinite(y) || !float.IsFinite(width) || !float.IsFinite(height) || width <= 0 || height <= 0)
                return new Rect(0,0,1,1); // Optional for hosts that predate safe-frame geometry.
            x = Mathf.Clamp(x,0,.95f); y = Mathf.Clamp(y,0,.95f);
            return new Rect(x,y,Mathf.Clamp(width,.01f,1-x),Mathf.Clamp(height,.01f,1-y));
        }
        // Preserve authored/user zoom and angle. Translate the camera only as much as
        // required to keep the static portrait envelope below the safe top edge and
        // outside horizontal cutouts. Depth is included for every corner, so yaw and
        // a projecting fringe cannot cross the notch despite a safe-looking centre.
        // The bottom is intentionally open: waist-up portraits extend behind the chat.
        // No animated head tracking: breathing/hair motion must not drag the camera.
        public static void ConstrainSafeFrame(Bounds region, Quaternion rotation, float aspect, float fov,
            Rect safeFrame, ref Vector3 focus, ref float distance)
        {
            float tangent = Mathf.Tan(fov*Mathf.Deg2Rad*.5f);
            float left = (2*safeFrame.xMin-1)*tangent*aspect;
            float right = (2*safeFrame.xMax-1)*tangent*aspect;
            float top = (2*safeFrame.yMax-1)*tangent;
            Quaternion inverse = Quaternion.Inverse(rotation);
            float lower = float.NegativeInfinity, upper = float.PositiveInfinity;
            for (int corner=0;corner<8;corner++)
            {
                var point = inverse*(Corner(region,corner)-focus)+Vector3.forward*distance;
                lower = Mathf.Max(lower,point.x-right*point.z);
                upper = Mathf.Min(upper,point.x-left*point.z);
            }
            // Normally the existing .82 frustum reserve is ample. A narrow landscape
            // safe window can require a minimal retreat before a translation exists.
            float retreat = Mathf.Max(0,(lower-upper)/Mathf.Max(.0001f,right-left));
            distance += retreat; lower -= right*retreat; upper -= left*retreat;
            float shiftX = Mathf.Clamp(0,lower,Mathf.Max(lower,upper)), shiftY = 0;
            for (int corner=0;corner<8;corner++)
            {
                var point = inverse*(Corner(region,corner)-focus)+Vector3.forward*distance;
                shiftY = Mathf.Max(shiftY,point.y-top*point.z);
            }
            focus += rotation*new Vector3(shiftX,shiftY,0);
        }
        public static Vector3 Corner(Bounds region,int index) => region.center+Vector3.Scale(region.extents,
            new Vector3((index&1)==0?-1:1,(index&2)==0?-1:1,(index&4)==0?-1:1));
        public static Rect ProjectedBounds(Bounds region, Camera camera)
        {
            Vector2 min = Vector2.one*float.PositiveInfinity, max = Vector2.one*float.NegativeInfinity;
            for(int corner=0;corner<8;corner++)
            {
                Vector2 point = camera.WorldToViewportPoint(Corner(region,corner));
                min=Vector2.Min(min,point); max=Vector2.Max(max,point);
            }
            return Rect.MinMaxRect(min.x,min.y,max.x,max.y);
        }
        // Moving a low subject into an upper screen region with a fixed pitch puts the
        // camera under the floor. Aim down by the region's elevation before solving
        // its perspective constraints; the small reserve keeps the eye above ground.
        public static float CompositionPitch(Rect area, float fov) => Mathf.Max(Pitch,
            Mathf.Atan(Mathf.Max(0,2*area.center.y-1)*Mathf.Tan(fov*Mathf.Deg2Rad*.5f))*Mathf.Rad2Deg+Pitch);
        // Fit into a virtual composition area while the camera continues rendering the entire
        // screen. Off-centre perspective includes depth: each of the eight corners is constrained
        // against all four edges. Changing UI space changes only the spring target, never pixels/FOV.
        public static void Compose(Bounds region, Quaternion rotation, float aspect, float fov,
            float size, float near, Rect area, out Vector3 focus, out float distance)
        {
            float tangent = Mathf.Tan(fov * Mathf.Deg2Rad * .5f);
            float cx = (2 * area.center.x - 1) * tangent * aspect;
            float cy = (2 * area.center.y - 1) * tangent;
            float hx = tangent * aspect * Mathf.Max(.05f,area.width) * .82f * Size(size);
            float hy = tangent * Mathf.Max(.05f,area.height) * .82f * Size(size);
            Quaternion inverse = Quaternion.Inverse(rotation);
            distance = near;
            for (int corner = 0; corner < 8; corner++)
            {
                Vector3 point = inverse * Vector3.Scale(region.extents,
                    new Vector3((corner & 1) == 0 ? -1 : 1, (corner & 2) == 0 ? -1 : 1, (corner & 4) == 0 ? -1 : 1));
                float horizontal = Mathf.Max((point.x-(cx+hx)*point.z)/hx, ((cx-hx)*point.z-point.x)/hx);
                float vertical = Mathf.Max((point.y-(cy+hy)*point.z)/hy, ((cy-hy)*point.z-point.y)/hy);
                distance = Mathf.Max(distance,Mathf.Max(Mathf.Max(horizontal,vertical),near*1.5f-point.z));
            }
            focus = region.center - rotation * new Vector3(cx * distance,cy * distance,0);
        }
        // Solve the frustum constraint for all 8 corners, including depth. A radial
        // approximation clips wide silhouettes after yaw or on a narrow tablet stage.
        public static float Distance(Bounds region, Quaternion rotation, float aspect, float fov, float size, float near)
        {
            float tangent = Mathf.Tan(fov * Mathf.Deg2Rad * .5f) * .82f * Size(size);
            float horizontal = tangent * Mathf.Max(.05f, aspect);
            Quaternion inverse = Quaternion.Inverse(rotation);
            float distance = near;
            for (int corner = 0; corner < 8; corner++)
            {
                var point = inverse * Vector3.Scale(region.extents,
                    new Vector3((corner & 1) == 0 ? -1 : 1, (corner & 2) == 0 ? -1 : 1, (corner & 4) == 0 ? -1 : 1));
                distance = Mathf.Max(distance, Mathf.Max(Mathf.Max(Mathf.Abs(point.x) / horizontal,
                    Mathf.Abs(point.y) / tangent) - point.z, near * 1.5f - point.z));
            }
            return distance;
        }
    }
}
