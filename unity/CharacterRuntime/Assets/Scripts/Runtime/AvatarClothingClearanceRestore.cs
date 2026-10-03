using UnityEngine;
namespace ModelSpace
{
    // Outer collision solve unwinds before arm inertia / gesture / body layers.
    [DefaultExecutionOrder(10)]
    public sealed class AvatarClothingClearanceRestore:MonoBehaviour
    {
        [System.NonSerialized] public AvatarClothingClearance driver;
        void Update(){if(driver)driver.Restore();}
    }
}
