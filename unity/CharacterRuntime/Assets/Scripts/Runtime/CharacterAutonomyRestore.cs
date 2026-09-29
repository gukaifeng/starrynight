using UnityEngine;
namespace ModelSpace
{
    [DefaultExecutionOrder(30)]
    public sealed class CharacterAutonomyRestore : MonoBehaviour
    {
        [System.NonSerialized] public CharacterAutonomy driver;
        void Update(){if(driver)driver.RestoreMorphs();}
    }
}
