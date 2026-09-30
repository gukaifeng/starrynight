using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
namespace ModelSpace
{
    public sealed class EnvironmentDirector : MonoBehaviour
    {
        public bool ToonPortrait { get; set; }
        public EnvironmentStage[] stages=Array.Empty<EnvironmentStage>();
        public Light key,fill,rim; public Renderer oldGround; public Camera viewCamera;
        EnvironmentStage visible,target;
        CharacterImageBackdrop backdrop;
        bool HasBackdrop=>backdrop && backdrop.Visible;
        StudioSettings settings=new StudioSettings(); EnvironmentSettings tuning=new EnvironmentSettings();
        public Action OnSettled; float reportAt=-1;
        float actorHeight=1.7f,opacity,fadeVelocity; bool decorations=true; bool initialized;
        public EnvironmentState State {
            get {
                var motion=visible ? visible.Ambient : null;
                return new EnvironmentState {selectedId=target ? target.Manifest.id : "",visibleId=visible ? visible.Manifest.id : "",palette=visible ? visible.Palette : "",decorations=decorations,angle=visible ? visible.Angle : 0,transitioning=opacity>0.001f || visible!=target || decorations!=tuning.decorations,transitionOpacity=opacity,keyAngle=key ? Mathf.DeltaAngle(180,key.transform.eulerAngles.y) : 0,keyHeight=key ? key.transform.eulerAngles.x : 0,
                    ambientNodes=motion ? motion.ActiveNodes : 0,rendererCount=motion ? motion.RendererCount : 0,vertexCount=motion ? motion.VertexCount : 0,
                    ambientRunning=motion && motion.isActiveAndEnabled && !motion.Suppressed,motionSuppressed=motion && motion.Suppressed,
                    ambientTime=motion ? motion.Elapsed : 0,clothOffset=motion ? motion.PeakClothOffset : 0,swayDegrees=motion ? motion.PeakSwayDegrees : 0};
            }
        }
        public void Bind(float height,string role=null)
        {
            actorHeight=height;
            if(!backdrop) backdrop=gameObject.AddComponent<CharacterImageBackdrop>();
            backdrop.Bind(viewCamera,role);
            // New character is still under the existing loading surface; retain the camera's own framing.
            foreach(var stage in stages) stage.transform.localScale=Vector3.one*(actorHeight/stage.Manifest.stage.referenceHeight);
            initialized=false;opacity=fadeVelocity=0;
        }
        public void Configure(StudioSettings value, bool immediate=false)
        {
            reportAt=Time.unscaledTime+2.2f;
            settings=value ?? new StudioSettings();tuning=settings.environment ?? new EnvironmentSettings();
            target=Array.Find(stages,s=>s.Manifest.id==settings.room) ?? stages[0];
            settings.room=target.Manifest.id;
            if(immediate || !initialized || !Application.isPlaying)
            {
                Commit();if(!HasBackdrop) visible.Apply(tuning,0,true);ApplyLighting(1);initialized=true;opacity=fadeVelocity=0;
            }
            if(oldGround) oldGround.enabled=false;
        }
        void Commit()
        {
            visible=target;decorations=tuning.decorations;
            foreach(var stage in stages) stage.gameObject.SetActive(stage==visible && !HasBackdrop);
            if(!HasBackdrop) {visible.SetDecorations(decorations);visible.Apply(tuning,0,true);}
        }
        void Update()
        {
            if(!initialized || !visible) return;
            float dt=Mathf.Min(Time.unscaledDeltaTime,.1f);
            bool change=visible!=target || decorations!=tuning.decorations;
            // A single reversible veil masks geometry replacement; rapid choices coalesce to the latest target.
            opacity=Mathf.SmoothDamp(opacity,change ? 1 : 0,ref fadeVelocity,.22f,Mathf.Infinity,dt);
            if(change && opacity>.995f) { Commit();ApplyLighting(1); }
            if(!change && opacity<.001f) {opacity=0;fadeVelocity=0;}
            if(visible==target && !HasBackdrop) visible.Apply(tuning,dt);
            ApplyLighting(1-Mathf.Exp(-dt*6));
            if(reportAt>0 && Time.unscaledTime>reportAt && !State.transitioning) { reportAt=-1;OnSettled?.Invoke(); }
        }
        void ApplyLighting(float t)
        {
            if(!visible || !key) return;
            var light=visible.Manifest.lighting;
            float roomScale=actorHeight/visible.Manifest.stage.referenceHeight;
            key.transform.rotation=Quaternion.Slerp(key.transform.rotation,Quaternion.Euler(StudioSettings.Safe(settings.lightHeight,20,75,48),180+StudioSettings.Safe(settings.lightAngle,-90,90,-35),0),t);
            key.intensity=Mathf.Lerp(key.intensity,StudioSettings.Safe(settings.lightIntensity,.6f,1.5f,1)*light.keyIntensity*(ToonPortrait?.7f:1),t);
            key.shadowStrength=Mathf.Lerp(key.shadowStrength,StudioSettings.Safe(settings.shadow,.15f,1,.75f),t);
            key.shadowBias=.02f;key.shadowNormalBias=.01f*roomScale;
            if(GraphicsSettings.currentRenderPipeline is UniversalRenderPipelineAsset pipeline) pipeline.shadowDistance=Mathf.Max(12,roomScale*18);
            key.color=Color.Lerp(key.color,EnvironmentStage.ColorValue(light.key),t);
            fill.intensity=Mathf.Lerp(fill.intensity,light.fillIntensity*(ToonPortrait?.12f:1),t);fill.color=Color.Lerp(fill.color,EnvironmentStage.ColorValue(light.fill),t);
            rim.intensity=Mathf.Lerp(rim.intensity,light.rimIntensity*(ToonPortrait?.1f:1),t);rim.color=Color.Lerp(rim.color,EnvironmentStage.ColorValue(light.fill),t);
            var ambient=EnvironmentStage.ColorValue(light.ambient);
            RenderSettings.ambientSkyColor=Color.Lerp(RenderSettings.ambientSkyColor,ambient,t);
            RenderSettings.ambientEquatorColor=Color.Lerp(RenderSettings.ambientEquatorColor,ambient*.57f,t);
            RenderSettings.ambientGroundColor=Color.Lerp(RenderSettings.ambientGroundColor,ambient*.25f,t);
            RenderSettings.fog=false;
            if(viewCamera) viewCamera.backgroundColor=Color.Lerp(viewCamera.backgroundColor,EnvironmentStage.ColorValue(light.sky),t);
        }
        void OnGUI()
        {
            if(opacity<=0 || Event.current.type!=EventType.Repaint) return;
            // Match the night canvas. Room edits must never flash a white full-screen veil.
            var previous=GUI.color;GUI.depth=-1000;GUI.color=new Color(.025f,.028f,.035f,opacity);
            GUI.DrawTexture(new Rect(0,0,Screen.width,Screen.height),Texture2D.whiteTexture);GUI.color=previous;
        }
    }
}
