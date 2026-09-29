using UnityEngine;

namespace ModelSpace
{
    // Exact damped spring: state includes velocity, so a new action can retarget mid-flight.
    // Distance is logarithmic; the same tuning feels consistent on differently sized rigs.
    public sealed class CameraFramingMotion
    {
        public const int Revision = 2;
        public const float ActionResponse = .62f, ReturnResponse = .82f, ControlResponse = .30f, LayoutResponse = 1.6f;
        public const float Damping = .80f; // One small overshoot (~1.5%), no repeated visible bounce.
        public const float LayoutDamping = .76f; // A deliberate, readable transition with a gentle rebound.
        Vector4 value, velocity, target;
        float pitch = FramingMath.Pitch, pitchVelocity, targetPitch = FramingMath.Pitch;
        bool initialized;
        public Vector3 Focus => new Vector3(value.x, value.y, value.z);
        public float Distance => Mathf.Exp(value.w);
        public float ZoomVelocity => velocity.w;
        public float Pitch => pitch;
        public bool Settled => initialized &&
            Vector3.Distance(Focus, new Vector3(target.x, target.y, target.z)) < Distance * .0001f &&
            new Vector3(velocity.x, velocity.y, velocity.z).magnitude < Distance * .001f &&
            Mathf.Abs(value.w-target.w) < .0001f && Mathf.Abs(velocity.w) < .001f &&
            Mathf.Abs(pitch-targetPitch) < .001f && Mathf.Abs(pitchVelocity) < .01f;

        public void SetTarget(Vector3 focus, float distance, float viewPitch = FramingMath.Pitch)
        {
            target = new Vector4(focus.x, focus.y, focus.z, Mathf.Log(Mathf.Max(.01f, distance)));
            targetPitch = viewPitch;
            if (!initialized) Snap();
        }
        public void Snap() { value = target; velocity = Vector4.zero; pitch = targetPitch; pitchVelocity = 0; initialized = true; }
        public void Step(float deltaTime, float response)
        {
            if (!initialized || deltaTime <= 0 || float.IsNaN(deltaTime) || float.IsInfinity(deltaTime)) return;
            // A resumed app / stall must not consume seconds of camera travel in one visible frame.
            float dt = Mathf.Min(deltaTime, 1f / 15f);
            float omega = 2 * Mathf.PI / Mathf.Max(.1f, response);
            float damping = response >= LayoutResponse ? LayoutDamping : Damping;
            float decayRate = damping * omega;
            float frequency = omega * Mathf.Sqrt(1-damping*damping);
            float decay = Mathf.Exp(-decayRate * dt);
            float cosine = Mathf.Cos(frequency * dt), sine = Mathf.Sin(frequency * dt);
            var offset = value-target;
            var previousVelocity = velocity;
            value = target + decay * (offset*cosine + (previousVelocity+decayRate*offset)*(sine/frequency));
            velocity = decay * (previousVelocity*cosine - (decayRate*previousVelocity+omega*omega*offset)*(sine/frequency));
            float pitchOffset = pitch-targetPitch, previousPitchVelocity = pitchVelocity;
            pitch = targetPitch + decay*(pitchOffset*cosine+(previousPitchVelocity+decayRate*pitchOffset)*(sine/frequency));
            pitchVelocity = decay*(previousPitchVelocity*cosine-(decayRate*previousPitchVelocity+omega*omega*pitchOffset)*(sine/frequency));
            if (Settled) Snap();
        }
    }
}
