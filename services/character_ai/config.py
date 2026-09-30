from dataclasses import dataclass, field
from pathlib import Path
import json, os

ROOT = Path(__file__).resolve().parents[2]

@dataclass
class Settings:
    data_dir: Path = field(default_factory=lambda: ROOT / '.local/character-ai')
    api_key: str = field(default='', repr=False)
    client_token: str = field(default='', repr=False)
    admin_token: str = field(default='', repr=False)
    host: str = 'https://dashscope.aliyuncs.com'
    character_model: str = 'qwen-flash-character-2026-02-26'
    tts_model: str = 'qwen-audio-3.1-tts-flash'
    asr_model: str = 'fun-asr-realtime'
    max_daily_calls: int = 60
    max_daily_tts_characters: int = 3000
    max_daily_asr_seconds: int = 180
    max_voice_designs: int = 2
    # Normal conversation is not a development smoke test. Old stored daily
    # thresholds are inert unless an operator explicitly opts back in.
    enforce_conversation_limits: bool = False
    # Runs beside audio, never before the first progressive text response.
    narration_timeout_seconds: float = 8.0
    paid_enabled: bool = True

    @classmethod
    def load(cls):
        path = Path(os.environ.get('STARRY_AI_CONFIG', ROOT / '.local/character-ai/settings.json'))
        data = json.loads(path.read_text()) if path.exists() else {}
        result = cls(**{k:v for k,v in data.items() if k in cls.__dataclass_fields__})
        result.data_dir = Path(result.data_dir)
        if os.environ.get('STARRY_AI_DISABLE_PAID') == '1': result.paid_enabled = False
        if not result.host.startswith('https://') or not result.host.endswith('.aliyuncs.com'):
            raise ValueError('Provider host must be an Alibaba HTTPS endpoint')
        return result
