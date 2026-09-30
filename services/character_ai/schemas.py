from typing import Literal
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field, field_validator
import re, hashlib

CONTROL_TEXT = re.compile(r'["\'](?:speech|dialogue|performance|beat_id|expression_intent|action_intent|vocal_events)["\']\s*:')

class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid')

class Thought(Strict):
    text: str = Field(max_length=160,description='读者可见的角色第一人称短心声，含我或咱，通常20字以内；不是回复计划、编排说明或旁白意图。不合适时省略thought。')
    visibility: Literal['visible','hidden','unlock_required'] = 'visible'

class StagedThought(Thought):
    stage: Literal['before','middle','after'] = Field(default='middle',description='心声出现的说话阶段；通常选middle或after。')
    after_text: str = Field(default='',max_length=220,
        description='可选精确锚点：复制本beat台词中的一小段，心声紧接其后；省略时使用stage，不填字符数或毫秒。')

class Speech(Strict):
    emotion: Literal['neutral','happy','sad','surprised','serious','worried'] = 'neutral'
    delivery: Literal['normal','soft','gentle','hesitant','teasing','whisper'] = 'normal'
    intensity: float = Field(default=.4, ge=0, le=1)

    @field_validator('delivery',mode='before')
    @classmethod
    def canonical_delivery(cls,value):
        # A small, documented vocabulary mapping, never invented speech.
        return {'playful':'teasing','warm':'gentle','tender':'gentle','calm':'soft'}.get(value,value) if isinstance(value,str) else value

    @field_validator('emotion',mode='before')
    @classmethod
    def canonical_emotion(cls,value):
        # Character models may use a familiar synonym despite the advertised
        # vocabulary. Translate known meanings to our supported speech controls;
        # unknown values still fail validation and never become arbitrary tags.
        return {'playful':'happy','teasing':'happy','cheerful':'happy','excited':'happy','joyful':'happy',
                'bright_smile':'happy','soft_smile':'happy','teasing_smile':'happy','shy_smile':'happy',
                'angry':'serious','pout':'serious','confused':'neutral','thinking':'neutral',
                'calm':'neutral','relaxed':'neutral','curious':'neutral',
                'soft':'neutral','gentle':'neutral','serene':'neutral','warm':'happy','tender':'happy','pleasant':'happy','contented':'happy',
                'concerned':'worried','anxious':'worried','amazed':'surprised',
                'melancholy':'sad'}.get(value,value) if isinstance(value,str) else value

class Dialogue(Strict):
    text: str = Field(min_length=1,max_length=220)
    speech: Speech = Field(default_factory=Speech)

    @field_validator('text')
    @classmethod
    def no_embedded_control_fields(cls,value):
        # Syntactically valid JSON can still hide a broken JSON fragment inside
        # its speech string. Reject via the existing single schema correction;
        # never display/read implementation fields as character dialogue.
        if CONTROL_TEXT.search(value):
            raise ValueError('dialogue.text contains control JSON; put speech/performance beside dialogue, never inside its text')
        return value

class PerformanceCue(Strict):
    group: str = Field(min_length=1,max_length=64)
    intent: str = Field(min_length=1,max_length=128)
    offset_ms: int = Field(default=0,ge=0,le=12000)
    active: bool = True

class Performance(Strict):
    expression_intent: str = Field(default='neutral',max_length=128)
    action_intent: str = Field(default='idle',max_length=128)
    intensity: float = Field(default=.4, ge=0, le=1)
    cues: list[PerformanceCue] = Field(default_factory=list,max_length=24,
        description='按可用分组组合多种表演；同组分时变化，不同组可并行。仅引用该组已声明的intent，不输出asset ID。')

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
    asides: list[StagedThought] = Field(default_factory=list,max_length=3)
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
    response_focus: str = Field(default='',max_length=100,
        description='本轮新增的具体内容摘要，先确定一个还没有讲过的新细节、观点或回应，再据此生成台词。不是台词或思考步骤。')
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

class TimelineBeat(Beat):
    asides: list[StagedThought] = Field(min_length=1,max_length=3,
        description='至少一条角色第一人称短心声，优先中段/结尾。只有用户要求纯台词时用hidden，不得省略整个字段。')

class TimelinePlan(Plan):
    response_focus: str = Field(min_length=1,max_length=100,
        description='本轮新增内容的一句话摘要，必须不同于recent_response_focus以及刚刚的回答。先写此项，再写beats；静默时写保持安静。')
    beats: list[TimelineBeat] = Field(default_factory=list,max_length=3)

class ShakeTimelinePlan(TimelinePlan):
    @field_validator('beats',mode='before')
    @classmethod
    def only_reaction(cls,value):
        # This event has a single task. Ignore an unwanted follow-up beat before
        # validating its speech controls or spending a repair call on it.
        return value[:1] if isinstance(value,list) else value

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

class ModelInteraction(Strict):
    kind: Literal['shake']
    intensity: float = Field(ge=0,le=1)

class Request(Strict):
    request_id: UUID
    character_id: str = Field(min_length=1,max_length=128,pattern=r'^[a-z][a-z0-9_.-]+$')
    text: str = Field(default='',max_length=500)
    trigger: Literal['user_message','appLaunch','firstLaunch','firstMeeting','characterSwitch','idle','story','model_shaken'] = 'user_message'
    interaction: ModelInteraction | None = None
    entry_id: UUID | None = None
    preferences: dict[str,str] = Field(default_factory=dict)
    memories: list[ClientMemory] = Field(default_factory=list,max_length=100)
    recent_messages: list[ContextMessage] = Field(default_factory=list,max_length=12)
    scene: dict[str,str] = Field(default_factory=dict)
    available_assets: list[str] = Field(default_factory=list,max_length=256)
    wants_audio: bool = True
    progressive_reply: bool = False
    timeline_reply: bool = False

    @field_validator('character_id')
    @classmethod
    def installed_character(cls,value):
        from .profiles import PROFILES
        if value not in PROFILES:raise ValueError('unknown character')
        return value

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
    # planning. Require an explicit first-person short aside, not only absence
    # of a few forbidden words. The 40-codepoint ceiling allows older genuine
    # asides; new generation targets 20. Keep the native replay guard in sync.
    if not text or len(text)>40 or not any(word in text for word in ('我','咱')):
        return None
    metadata=('用户','让对方','对方感受','需传递','正式问候','边界清晰','回应策略',
              '准备回复','作为角色','符合人设','需要表现','应当表达','台词','情绪状态','遵守',
              '编排','提示词','分享邀请','回复意图')
    planning=(r'(?:引出|引导|转入|转向|延续|承接).{0,18}(?:话题|邀请)',
              r'(?:营造|延续|保持|维持|烘托|渲染).{0,18}氛围',
              r'(?:结合|根据|符合|体现).{0,14}(?:人设|设定|偏好|上下文)',
              r'(?:选择|使用|采用).{0,18}(?:语气|措辞|表情|动作)')
    return None if any(word in text for word in metadata) or any(re.search(p,text) for p in planning) else text
