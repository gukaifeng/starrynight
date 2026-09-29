using UnityEngine;
namespace ModelSpace
{
    // Undo the outer performance layer before parameters (40), speech (50),
    // expressions (55), gaze (80), and secondary motion restore/evaluate.
    [DefaultExecutionOrder(35)]
    public sealed class CharacterPerformanceRestore : MonoBehaviour
    {
        [System.NonSerialized] public CharacterPerformanceDriver driver;
        void Update() { if(driver)driver.RestoreMorphs(); }
    }
}
