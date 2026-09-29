using UnityEngine;

public static class OutdoorEnvironmentBuilder
{
    public static Transform Create(string id) => RefinedEnvironmentBuilder.CreateOutdoor(id);
}
