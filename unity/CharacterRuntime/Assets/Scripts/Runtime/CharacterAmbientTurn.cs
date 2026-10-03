using UnityEngine;

namespace ModelSpace
{
    // Host presentation motion, independent of authored bones, user gestures,
    // saved view settings and shake-reaction accounting.
    public sealed class CharacterAmbientTurn
    {
        public const float IdleYaw=8f,IdlePitch=3.2f,SpeechYaw=3.2f,SpeechPitch=1.3f;
        Vector2 offset,target,velocity;
        System.Random random=new System.Random();
        float remaining=.8f;
        int legs;
        bool lastSpeaking,blocked=true;
        public Vector2 Offset=>offset;
        public int Waypoints {get;private set;}
        public bool Speaking {get;private set;}
        public bool Suppressed {get;private set;}=true;
        public float Travel {get;private set;}
        public void Reset(int seed)
        {
            random=new System.Random(seed);offset=target=velocity=Vector2.zero;
            remaining=Range(.8f,1.8f);legs=Waypoints=0;Travel=0;blocked=true;lastSpeaking=Speaking=false;Suppressed=true;
        }
        float Range(float low,float high)=>Mathf.Lerp(low,high,(float)random.NextDouble());
        public void Step(float deltaTime,bool allowed,bool speaking)
        {
            if(!float.IsFinite(deltaTime)||deltaTime<=0)return;
            float dt=Mathf.Min(deltaTime,.05f);Speaking=speaking;Suppressed=!allowed;
            if(!allowed) {target=Vector2.zero;remaining=1.1f;legs=0;blocked=true;}
            else
            {
                if(blocked) {blocked=false;remaining=Range(.65f,1.4f);}
                if(speaking!=lastSpeaking) {remaining=Mathf.Min(remaining,.25f);legs=0;target=Vector2.zero;}
                remaining-=dt;
                if(remaining<=0)
                {
                    if(legs==0)
                    {
                        // Every phrase of movement comes home and rests, rather
                        // than a perpetual sine wave or a fixed repeating loop.
                        target=Vector2.zero;legs=random.Next(2,5);
                        remaining=speaking?Range(.35f,.95f):Range(2.2f,5.4f);
                    }
                    else
                    {
                        float angle=Range(-Mathf.PI,Mathf.PI),radius=Range(.5f,1);
                        var next=new Vector2(Mathf.Cos(angle)*(speaking?SpeechYaw:IdleYaw),Mathf.Sin(angle)*(speaking?SpeechPitch:IdlePitch))*radius;
                        if(Vector2.Dot(next,target)>.6f*next.magnitude*target.magnitude)next=-next;
                        target=next;legs--;Waypoints++;
                        remaining=speaking?Range(.9f,1.65f):Range(1.45f,2.5f);
                    }
                }
            }
            lastSpeaking=speaking;
            var before=offset;
            offset=Vector2.SmoothDamp(offset,target,ref velocity,!allowed?.28f:speaking?.46f:.64f,12,dt);
            offset=new Vector2(Mathf.Clamp(offset.x,-IdleYaw,IdleYaw),Mathf.Clamp(offset.y,-IdlePitch,IdlePitch));
            if(!allowed && offset.sqrMagnitude<.000001f && velocity.sqrMagnitude<.00001f)offset=velocity=Vector2.zero;
            Travel+=(offset-before).magnitude;
        }
    }
}
