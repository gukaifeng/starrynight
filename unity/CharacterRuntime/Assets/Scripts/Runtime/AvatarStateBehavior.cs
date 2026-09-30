using System;
using System.Linq;
using UnityEngine;

namespace ModelSpace
{
    // Only explicitly recognized state behaviors are recreated from typed data.
    public sealed class AvatarStateBehavior : StateMachineBehaviour
    {
        public AvatarBehavior[] operations;
        public override void OnStateEnter(Animator animator,AnimatorStateInfo state,int layerIndex)
        {
            var driver=animator.GetComponentInParent<AvatarControlDriver>();if(!driver)return;
            foreach(var op in operations)
            {
                if(op.kind=="layer-weight" || op.kind=="playable-weight") {driver.Weight(op.playable,op.layer,op.weight,op.duration);continue;}
                if(op.kind=="tracking") {driver.Tracking(op.eyes,op.mouth);continue;}
                if(op.kind!="parameter-driver" || op.parameters==null)continue;
                foreach(var p in op.parameters)
                {
                    float value=p.value;
                    if(p.operation==1)value=driver.Get(p.name)+value;
                    else if(p.operation==2)
                    {
                        var spec=driver.profile.parameters.FirstOrDefault(v=>v.name==p.name);
                        value=spec?.kind=="bool"?(UnityEngine.Random.value<p.chance?1:0):spec?.kind=="int"?UnityEngine.Random.Range(Mathf.RoundToInt(p.minimum),Mathf.RoundToInt(p.maximum)+1):UnityEngine.Random.Range(p.minimum,p.maximum);
                    }
                    else if(p.operation==3) {value=driver.Get(p.source);if(p.convertRange)value=Mathf.Lerp(p.destMin,p.destMax,Mathf.InverseLerp(p.sourceMin,p.sourceMax,value));}
                    else if(p.operation!=0)continue;
                    driver.Set(p.name,value);
                }
            }
        }
        public override void OnStateExit(Animator animator,AnimatorStateInfo state,int layerIndex)
        {
            var driver=animator.GetComponentInParent<AvatarControlDriver>();if(!driver)return;
            foreach(var op in operations)if(op.kind=="layer-weight" || op.kind=="playable-weight")driver.Weight(op.playable,op.layer,op.weight,0);
        }
    }
}
