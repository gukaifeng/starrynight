using UnityEngine;
namespace ModelSpace
{
    [DefaultExecutionOrder(20)]
    public sealed class HostEmotionMotionRestore : MonoBehaviour
    {
        [System.NonSerialized] public HostEmotionMotion driver;
        void Update(){if(driver)driver.RestorePose();}
    }
}
