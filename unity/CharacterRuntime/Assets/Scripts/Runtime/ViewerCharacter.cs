using UnityEngine;

namespace ModelSpace
{
    [System.Serializable] public class FramingEnvelope
    {
        public string action;
        public Bounds localBounds;
    }
    // Each character owns its own rig and capabilities; inactive characters do no animation work.
    public sealed class ViewerCharacter : MonoBehaviour
    {
        public TextAsset contractAsset;
        CharacterManifest manifest;
        public CharacterManifest Manifest => manifest ?? (manifest=JsonUtility.FromJson<CharacterManifest>(contractAsset.text));
        public void ApplyContract()
        {
            if(!contractAsset) throw new System.InvalidOperationException("CHARACTER_MANIFEST_MISSING");
            manifest=JsonUtility.FromJson<CharacterManifest>(contractAsset.text); CharacterContract.Validate(manifest);
            modelId=manifest.id; displayName=manifest.display.name; conversationStart=manifest.rig.conversationStart;
            actions=System.Array.ConvertAll(System.Array.FindAll(manifest.actions,a=>a.id!="Idle"),a=>a.id);
        }
        public string modelId;
        public string displayName;
        [Range(.5f,1.2f)] public float portraitFramingScale = 1f;
        [Range(.42f,.7f)] public float conversationStart = .42f;
        public string[] actions = { "Wave", "Jump", "Dance", "No" };
        public FramingEnvelope[] framingEnvelopes;
        public bool useAuthoredRestBounds;
        public Bounds authoredRestBounds;
        public Bounds FramingBounds(string action)
        {
            var envelope = System.Array.Find(framingEnvelopes ?? System.Array.Empty<FramingEnvelope>(), e => e.action == action);
            if (envelope == null) throw new System.InvalidOperationException("缺少动作取景范围，请重新导出 Unity 工程：" + action);
            var local = envelope.localBounds;
            var world = new Bounds(transform.TransformPoint(local.center), Vector3.zero);
            for (int corner = 0; corner < 8; corner++)
                world.Encapsulate(transform.TransformPoint(local.center + Vector3.Scale(local.extents,
                    new Vector3((corner & 1) == 0 ? -1 : 1,(corner & 2) == 0 ? -1 : 1,(corner & 4) == 0 ? -1 : 1))));
            return world;
        }
        public Bounds RestBounds()
        {
            if (useAuthoredRestBounds)
            {
                var authored = new Bounds(transform.TransformPoint(authoredRestBounds.center),Vector3.zero);
                for (int corner=0;corner<8;corner++)
                    authored.Encapsulate(transform.TransformPoint(authoredRestBounds.center+Vector3.Scale(authoredRestBounds.extents,
                        new Vector3((corner&1)==0?-1:1,(corner&2)==0?-1:1,(corner&4)==0?-1:1))));
                return authored;
            }
            var renderers = GetComponentsInChildren<Renderer>(true);
            if (renderers.Length == 0) throw new System.InvalidOperationException("模型没有可显示的内容");
            var bounds = new Bounds(); bool initialized = false;
            foreach (var renderer in renderers)
            {
                if(!renderer.enabled || !VisibleWithinCharacter(renderer.transform))continue;
                // Skinned localBounds reserves room for animation; fit the actual neutral mesh.
                var skin = renderer as SkinnedMeshRenderer;
                var filter = renderer.GetComponent<MeshFilter>();
                Mesh mesh = skin ? skin.sharedMesh : filter ? filter.sharedMesh : null;
                if (!mesh) continue;
                Bounds local = mesh.bounds;
                for (int corner = 0; corner < 8; corner++)
                {
                    var p = renderer.transform.TransformPoint(local.center + Vector3.Scale(local.extents,
                        new Vector3((corner & 1) == 0 ? -1 : 1, (corner & 2) == 0 ? -1 : 1, (corner & 4) == 0 ? -1 : 1)));
                    if (!initialized) { bounds = new Bounds(p, Vector3.zero); initialized = true; }
                    else bounds.Encapsulate(p);
                }
            }
            if (!initialized) throw new System.InvalidOperationException("模型网格缺失");
            return bounds;
        }
        bool VisibleWithinCharacter(Transform item)
        {
            // An inactive library character still needs valid bounds for validation
            // and preloading. Only authored hidden descendants are excluded.
            for(var node=item;node && node!=transform;node=node.parent)
                if(!node.gameObject.activeSelf)return false;
            return true;
        }
    }
}
