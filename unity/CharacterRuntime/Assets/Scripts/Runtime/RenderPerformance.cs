using System;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Rendering;

namespace ModelSpace
{
    // Player-loop intervals, not a claim about display presentation or physical-device GPU time.
    // Fixed storage avoids per-frame allocations; sort/JSON only once per two-second window.
    public sealed class RenderPerformance : MonoBehaviour
    {
        [Serializable] sealed class Sample
        {
            public int schemaVersion=1,presentationId,targetFPS,appliedFPS,frameCount,over16_7ms,over8_3ms,width,height;
            public string kind="event",name="performance",measurement="unity-player-loop";
            public string modelId;
            public double fps,p95Ms,p99Ms,worstMs,refreshHz,windowSeconds;
        }
        readonly double[] intervals=new double[1024];
        int count,presentation,requestedFPS=120;
        double previous,warmUntil,sum;
        bool configured;
        ViewerController viewer;
        void Awake() { viewer = GetComponent<ViewerController>(); }
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")] static extern void MSNativeSendEvent(string json);
#endif
        public void Configure(int target,int id)
        {
            requestedFPS = target >= 120 ? 120 : 60;
            Application.targetFrameRate = requestedFPS;
            QualitySettings.vSyncCount = 0;
            OnDemandRendering.renderFrameInterval = 1;
            presentation=id;configured=true;Restart();
        }
        void Restart(){count=0;sum=0;previous=Time.realtimeSinceStartupAsDouble;warmUntil=previous+1;}
        void OnApplicationPause(bool paused){Restart();}
        void OnApplicationFocus(bool focus){Restart();}
        void Update()
        {
            double now=Time.realtimeSinceStartupAsDouble,dt=now-previous;previous=now;
            if(!configured || now<warmUntil || dt<=0)return;
            intervals[count++]=dt*1000;sum+=dt;
            if(sum<2 && count<intervals.Length)return;
            Array.Sort(intervals,0,count);
            int slow60=0,slow120=0;
            for(int i=0;i<count;i++){if(intervals[i]>1000.0/60)slow60++;if(intervals[i]>1000.0/120)slow120++;}
            var sample=new Sample{modelId=viewer ? viewer.ActiveModelId : "",presentationId=presentation,targetFPS=requestedFPS,appliedFPS=Application.targetFrameRate,frameCount=count,
                fps=count/sum,windowSeconds=sum,p95Ms=intervals[Math.Min(count-1,(int)Math.Ceiling(count*.95)-1)],
                p99Ms=intervals[Math.Min(count-1,(int)Math.Ceiling(count*.99)-1)],worstMs=intervals[count-1],
                over16_7ms=slow60,over8_3ms=slow120,refreshHz=Screen.currentResolution.refreshRateRatio.value,
                width=Screen.width,height=Screen.height};
            string json=JsonUtility.ToJson(sample);
#if UNITY_IOS && !UNITY_EDITOR
            MSNativeSendEvent(json);
#else
            Debug.Log("MODELSPACE_PERFORMANCE "+json);
#endif
            count=0;sum=0;
        }
    }
}
