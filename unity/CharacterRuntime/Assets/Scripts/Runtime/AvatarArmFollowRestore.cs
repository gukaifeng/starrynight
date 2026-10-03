using UnityEngine;
namespace ModelSpace
{
    // Undo the outer arm overlay before inner host/source/continuity overlays.
    [DefaultExecutionOrder(15)]
    public sealed class AvatarArmFollowRestore:MonoBehaviour
    {
        public AvatarArmFollow driver;
        void Update(){if(driver)driver.Restore();}
    }
}
