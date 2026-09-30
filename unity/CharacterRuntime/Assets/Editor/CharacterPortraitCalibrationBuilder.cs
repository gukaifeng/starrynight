using System;
using UnityEngine;
using ModelSpace;

public static class CharacterPortraitCalibrationBuilder
{
    public static void Prepare(ViewerCharacter character)
    {
        var root=character.transform;var rest=character.RestBounds();var rig=character.Manifest.rig;
        var head=CharacterContract.Resolve(root,rig.head);
        var left=string.IsNullOrEmpty(rig.leftEye)?null:CharacterContract.Resolve(root,rig.leftEye);
        var right=string.IsNullOrEmpty(rig.rightEye)?null:CharacterContract.Resolve(root,rig.rightEye);
        float span=left && right?Vector3.Distance(left.position,right.position):0;
        bool eyes=span>rest.size.y*.02f && span<rest.size.y*.18f;
        float faceHeight=eyes?Mathf.Clamp(span*2.5f,rest.size.y*.12f,rest.size.y*.38f):rest.size.y*.23f;
        Vector3 face=eyes?(left.position+right.position)*.5f-Vector3.up*span*.30f:
            head?head.position+Vector3.up*faceHeight*.28f:rest.center+Vector3.up*rest.size.y*.30f;
        // Body/shoulder width remains bounded without letting long tails decide
        // portrait magnification. All values are stored in model-local space.
        float halfWidth=faceHeight*1.02f;
        var region=new Bounds();region.SetMinMax(
            new Vector3(face.x-halfWidth,Mathf.Max(rest.min.y,face.y-faceHeight*1.6f),rest.min.z),
            new Vector3(face.x+halfWidth,rest.max.y+rest.size.y*.025f,rest.max.z));
        var local=new Bounds(root.InverseTransformPoint(region.center),Vector3.zero);
        for(int i=0;i<8;i++)local.Encapsulate(root.InverseTransformPoint(FramingMath.Corner(region,i)));
        character.portrait=new CharacterPortrait {localFace=root.InverseTransformPoint(face),
            localFaceHeight=root.InverseTransformVector(Vector3.up*faceHeight).magnitude,
            localRegion=local,measurement=eyes?"neutral-eye-spacing":"neutral-head-height-fallback"};
        Debug.Log("CHARACTER_PORTRAIT "+character.modelId+" height="+rest.size.y+" face="+face+" faceHeight="+faceHeight+" via="+character.portrait.measurement);
    }
}
