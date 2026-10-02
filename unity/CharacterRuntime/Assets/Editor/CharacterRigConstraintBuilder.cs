using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Animations;

// Audited numeric data becomes engine-native constraints. No avatar SDK code
// enters the player. Local-space / frozen VRC variants are rejected upstream.
public static class CharacterRigConstraintBuilder
{
    [Serializable] sealed class Pet {public int initialMode;public string happyOption,unhappyOption;public float duration;}
    [Serializable] sealed class Catalog {public int schemaVersion;public string coordinateSystem;public Rotation[] rotations;}
    [Serializable] sealed class Source {public string path;public float weight;}
    [Serializable] sealed class Rotation {public string path;public Source[] sources;public float weight;public bool active;public Vector3 rest,offset;public bool[] axes;}
    static Vector3 MirrorEuler(Vector3 value)
    {
        var q=Quaternion.Euler(value);
        return new Quaternion(q.x,-q.y,-q.z,q.w).eulerAngles;
    }
    public static void Prepare(GameObject character,string folder)
    {
        string petFile=folder+"/pet-feedback.json";
        if(File.Exists(petFile))
        {
            var spec=JsonUtility.FromJson<Pet>(File.ReadAllText(petFile));
            var manifest=character.GetComponent<ModelSpace.ViewerCharacter>().Manifest;
            if(spec.initialMode<0 || spec.initialMode>2 || !float.IsFinite(spec.duration) || spec.duration<.1f || spec.duration>10 ||
               !manifest.performance.options.Any(o=>o.id==spec.happyOption) || !manifest.performance.options.Any(o=>o.id==spec.unhappyOption))
                throw new Exception("PET_FEEDBACK_SPEC_INVALID");
            var pet=character.AddComponent<ModelSpace.CharacterPetFeedback>();
            pet.initialMode=spec.initialMode;pet.happyOption=spec.happyOption;pet.unhappyOption=spec.unhappyOption;pet.duration=spec.duration;
        }
        string file=folder+"/rig-constraints.json";
        if(!File.Exists(file))return;
        var catalog=JsonUtility.FromJson<Catalog>(File.ReadAllText(file));
        if(catalog.schemaVersion!=1 || catalog.coordinateSystem!="unity-source-mirror-x" ||
           catalog.rotations==null || catalog.rotations.Length>64)throw new Exception("RIG_CONSTRAINT_SCHEMA_INVALID");
        var seen=new HashSet<string>();
        foreach(var spec in catalog.rotations)
        {
            if(!seen.Add(spec.path) || !float.IsFinite(spec.weight) || spec.weight<0 || spec.weight>1 ||
               spec.axes?.Length!=3 || spec.sources==null || spec.sources.Length<1 || spec.sources.Length>16)
                throw new Exception("RIG_CONSTRAINT_SPEC_INVALID");
            var target=ModelSpace.CharacterContract.Resolve(character.transform,spec.path);
            if(!target)throw new Exception("RIG_CONSTRAINT_TARGET_MISSING: "+spec.path);
            var sources=new List<ConstraintSource>();
            foreach(var source in spec.sources)
            {
                var transform=ModelSpace.CharacterContract.Resolve(character.transform,source.path);
                if(!transform || transform==target || !float.IsFinite(source.weight) || source.weight<=0)
                    throw new Exception("RIG_CONSTRAINT_SOURCE_INVALID: "+source.path);
                sources.Add(new ConstraintSource {sourceTransform=transform,weight=source.weight});
            }
            var constraint=target.gameObject.AddComponent<RotationConstraint>();
            constraint.constraintActive=false;
            constraint.SetSources(sources);
            constraint.rotationAtRest=MirrorEuler(spec.rest);
            constraint.rotationOffset=MirrorEuler(spec.offset);
            constraint.rotationAxis=(spec.axes[0]?Axis.X:Axis.None)|(spec.axes[1]?Axis.Y:Axis.None)|(spec.axes[2]?Axis.Z:Axis.None);
            constraint.weight=spec.weight;constraint.locked=true;constraint.constraintActive=spec.active;
            EditorUtility.SetDirty(constraint);
        }
    }
}
