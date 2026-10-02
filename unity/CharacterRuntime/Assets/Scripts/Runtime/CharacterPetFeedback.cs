using System;
using System.Linq;
using UnityEngine;

namespace ModelSpace
{
    // Original PetMode choices and face presets, adapted to a local head tap.
    // VRChat hand contacts/networking are not required. Repeated taps extend
    // the reaction, then restore the user's previous expression selection.
    public sealed class CharacterPetFeedback : MonoBehaviour
    {
        public int initialMode=1;
        public string happyOption,unhappyOption;
        public float duration=1.6f;
        public int Mode {get;private set;}=1;
        public int ReactionCount {get;private set;}
        CharacterPerformanceDriver performance;
        string[] previous;
        float until;
        public bool ApplyingExpression {get;private set;}
        void OnEnable(){Mode=initialMode;performance=null;previous=null;}
        public void Configure(string mode)
        {
            Mode=mode=="off"?0:mode=="happy"?1:mode=="unhappy"?2:throw new ArgumentException("PET_MODE_INVALID");
            if(Mode==0)Restore();
        }
        public void ResetMode(){Restore();Mode=initialMode;}
        public bool Tap(CharacterPerformanceDriver driver)
        {
            if(Mode==0 || !driver || !driver.IsBoundTo(GetComponent<ViewerCharacter>()))return false;
            if(performance!=driver || previous==null)
            {
                performance=driver;
                var profile=GetComponent<ViewerCharacter>().Manifest.performance;
                previous=driver.Selections.Where(id=>profile.options.Any(o=>o.id==id && o.group=="expression")).ToArray();
            }
            string error;
            ApplyingExpression=true;
            try {error=driver.Replace("expression",new[]{Mode==1?happyOption:unhappyOption});}
            finally {ApplyingExpression=false;}
            if(error!=null){performance=null;previous=null;return false;}
            until=Time.unscaledTime+duration;ReactionCount++;return true;
        }
        void Update(){if(previous!=null && Time.unscaledTime>=until)Restore();}
        void OnDisable(){Restore();}
        public void Restore()
        {
            var driver=performance;var snapshot=previous;
            previous=null;performance=null;
            if(snapshot!=null && driver && driver.IsBoundTo(GetComponent<ViewerCharacter>()))
                driver.Replace("expression",snapshot);
        }
    }
}
