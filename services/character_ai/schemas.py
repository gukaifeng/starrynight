from typing import Literal
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field, field_validator
import re, hashlib

class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid')

class Thought(Strict):
    text: str = Field(max_length=160)
    visibility: Literal['visible','hidden','unlock_required'] = 'visible'

class Speech(Strict):
    emotion: Literal['neutral','happy','sad','surprised','serious','worried'] = 'neutral'
    delivery: Literal['normal','soft','gentle','hesitant','teasing','whisper'] = 'normal'
    intensity: float = Field(default=.4, ge=0, le=1)

    @field_validator('emotion',mode='before')
    @classmethod
    def canonical_emotion(cls,value):
        # Character models may use a familiar synonym despite the advertised
        # vocabulary. Translate known meanings to our supported speech controls;
        # unknown values still fail validation and never become arbitrary tags.
        return {'playful':'happy','cheerful':'happy','excited':'happy','joyful':'happy',
                'calm':'neutral','relaxed':'neutral','curious':'neutral',
                'concerned':'worried','anxious':'worried','amazed':'surprised',
                'melancholy':'sad'}.get(value,value) if isinstance(value,str) else value

class Dialogue(Strict):
    text: str = Field(min_length=1,max_length=220)
    speech: Speech = Field(default_factory=Speech)

class Performance(Strict):
    expression_intent: str = Field(default='neutral',max_length=40)
    action_intent: str = Field(default='idle',max_length=40)
    intensity: float = Field(default=.4, ge=0, le=1)

class NarrationIntent(Strict):
    purpose: str = Field(default='',max_length=100)
    include_performed_narration: bool = True
    include_literary_narration: bool = True

VocalType = Literal['gasp','sigh','throat_clear','giggle','laugh','cough','snort']
class Vocal(Strict):
    event: VocalType
    intensity: float = Field(default=.3, ge=0, le=1)
    describe_in_narration: bool = False
    visual_sync: Performance | None = None

class Beat(Strict):
    beat_id: str = Field(pattern=r'^[a-zA-Z0-9_-]{1,32}$')
    thought: Thought | None = None
    dialogue: Dialogue | None = None
    performance: Performance = Field(default_factory=Performance)
    narration_intent: NarrationIntent | None = None
    vocal_events: list[Vocal] = Field(default_factory=list,max_length=2)

    @field_validator('beat_id',mode='before')
    @classmethod
    def canonical_id(cls,value):
        # Some character-model outputs use Chinese beat labels despite the JSON
        # pattern. IDs are routing metadata: normalize, never spend a second LLM
        # request correcting an identifier that has no effect on dialogue meaning.
        if isinstance(value,str) and 0<len(value)<=120 and not re.fullmatch(r'[a-zA-Z0-9_-]{1,32}',value):
            return 'beat_'+hashlib.sha256(value.encode()).hexdigest()[:16]
        return value

    @field_validator('thought',mode='before')
    @classmethod
    def explicit_thought(cls,value):
        # The endpoint sometimes abbreviates an optional thought object as text.
        # Normalize its representation; content and the 160-character limit stay.
        if isinstance(value,str): return {'text':value,'visibility':'visible'} if value.strip() else None
        return value

class Interpretation(Strict):
    dominant_emotion: str = Field(default='neutral',max_length=40)
    attitude_to_user: str = Field(default='friendly',max_length=80)

class MemoryProposal(Strict):
    content: str = Field(min_length=2,max_length=160)
    importance: float = Field(default=.5,ge=0,le=1)
    type: Literal['user_fact','shared_event'] = 'user_fact'

class Plan(Strict):
    reply_type: Literal['normal_reply','idle_event','fallback'] = 'normal_reply'
    state_interpretation: Interpretation = Field(default_factory=Interpretation)
    idle_decision: Literal['do_nothing','visual_only','thought_only','proactive_speech'] | None = None
    beats: list[Beat] = Field(default_factory=list,max_length=3)
    suggested_state_delta: dict[str,float] = Field(default_factory=dict)
    memory_updates: list[MemoryProposal] = Field(default_factory=list,max_length=2)

    @field_validator('beats')
    @classmethod
    def unique_ids(cls, value):
        if len({b.beat_id for b in value}) != len(value): raise ValueError('duplicate beat_id')
        if sum(len(b.vocal_events) for b in value)>2: raise ValueError('too many vocal events')
        return value

class Narration(Strict):
    beat_id: str
    mode: Literal['performed','literary']
    text: str = Field(min_length=1,max_length=160)
    visual_grounding: Literal['exact','approximate','none']
    # Structured citations let code reject invented assets/effects before display.
    evidence: list[str] = Field(default_factory=list,max_length=4)

class NarrationResult(Strict):
    narrations: list[Narration] = Field(default_factory=list,max_length=6)

class ClientMemory(Strict):
    id: str = Field(max_length=64)
    text: str = Field(max_length=300)

class ContextMessage(Strict):
    role: Literal['user','assistant']
    text: str = Field(max_length=700)

class Request(Strict):
    request_id: UUID
    character_id: Literal['anime-kipfel','anime-mamehinata']
    text: str = Field(default='',max_length=500)
    trigger: Literal['user_message','appLaunch','firstLaunch','firstMeeting','characterSwitch','idle','story'] = 'user_message'
    entry_id: UUID | None = None
    preferences: dict[str,str] = Field(default_factory=dict)
    memories: list[ClientMemory] = Field(default_factory=list,max_length=100)
    recent_messages: list[ContextMessage] = Field(default_factory=list,max_length=12)
    scene: dict[str,str] = Field(default_factory=dict)
    available_assets: list[str] = Field(default_factory=list,max_length=256)
    wants_audio: bool = True

    @field_validator('preferences','scene')
    @classmethod
    def bounded_context(cls,value):
        if len(value)>12 or any(len(k)>40 or len(v)>500 for k,v in value.items()):
            raise ValueError('context too large')
        return value

def visible_text(text: str) -> str:
    # Provider markup and asset control strings never reach the conversation UI.
    text = re.sub(r'\[(?:gasp|sighing|clears throat|giggles|laughing|cough|snorts|happy|sad|angry|whispering|excited|amazed|serious|empathetic)\]', '', text, flags=re.I)
    text = re.sub(r'<[^>]{1,120}>','',text)
    return text.strip()

def visible_thought(text: str) -> str | None:
    text=visible_text(text)
    # This field is fictional character monologue, never a report on reply
    # planning or instruction-following. Drop leakage; don't invent replacement.
    metadata=('用户','让对方','对方感受','需传递','正式问候','边界清晰','回应策略',
              '准备回复','作为角色','符合人设','需要表现','应当表达','台词','情绪状态','遵守')
    return text if text and not any(word in text for word in metadata) else None
