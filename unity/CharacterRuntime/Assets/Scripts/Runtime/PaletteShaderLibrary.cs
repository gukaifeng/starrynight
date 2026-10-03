using System.Linq;
using UnityEngine;
namespace ModelSpace
{
    public sealed class PaletteShaderLibrary : ScriptableObject
    {
        public PaletteShaderEntry[] entries;
        public PaletteMaterialLabel[] labels;
        public Shader Variant(Shader source) => source ? entries?.FirstOrDefault(x=>x.original==source.name)?.shader : null;
        public string Label(string name) => labels?.FirstOrDefault(x=>x.key==name)?.label ?? name;
    }
}
