using UnityEngine;
using ModelSpace;

public static class CharacterRoomBuilder
{
    public static void Create(CharacterStudioDriver driver, Light key, Light fill, Light rim, Renderer oldGround)
    {
        driver.key = key; driver.fill = fill; driver.rim = rim; driver.oldGround = oldGround;
        driver.rooms = new Transform[3];
        string[] names = { "sunroom", "studio", "evening" };
        for (int i = 0; i < names.Length; i++)
        {
            driver.rooms[i] = RefinedEnvironmentBuilder.CreateRoom(names[i]);
            driver.rooms[i].gameObject.SetActive(i == 0);
        }
    }
}
