using UnityEngine;
namespace ModelSpace
{
    // Undo inner natural-body offsets after arm/emotion restores, before
    // continuity and native Animator evaluate the next frame.
    [DefaultExecutionOrder(22)]
    public sealed class AvatarNaturalMotionRestore:MonoBehaviour
    {
        [System.NonSerialized] public AvatarNaturalMotion driver;
        void Update(){if(driver)driver.Restore();}
    }
}
