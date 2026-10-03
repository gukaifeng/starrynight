using UnityEngine;

namespace ModelSpace
{
    // A separate script asset is required because this component is serialized
    // in character prefabs. Restore overlays before the author Animator updates.
    [DefaultExecutionOrder(25)]
    public sealed class SourceMotionPreviewRestore:MonoBehaviour
    {
        public SourceMotionPreview driver;
        void Update(){if(driver)driver.RestorePose();}
    }
}
