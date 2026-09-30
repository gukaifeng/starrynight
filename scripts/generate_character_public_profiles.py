"""Build offline public cards from the worker's explicit presentation allowlist."""
import json
from pathlib import Path
import sys

def generate(root:Path):
    sys.path.insert(0,str(root))
    from services.character_ai.public_profiles import public_catalog
    path=root/'ios/CharacterHost/Resources/CharacterPublicProfiles.json'
    path.write_text(json.dumps(public_catalog(),ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':generate(Path(__file__).resolve().parents[1])
