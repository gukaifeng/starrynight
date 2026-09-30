"""Complete, read-only developer view of authored and effective AI configuration."""
import importlib
import json
from datetime import datetime, timezone
from pathlib import Path
from . import prompts, schemas
from .profiles import PROFILES, assets
from .provider import structured_messages, structured_payload, EMOTIONS, DELIVERY, VOCALS
from .public_profiles import public_profile

def report(settings,engine,owner,request):
    char=request.character_id;store=engine.store
    context=engine.context(owner,request,persist=False)
    sections=[]
    def add(id,title,detail,value):
        sections.append(dict(id=id,title=title,detail=detail,
                             content=value if isinstance(value,str) else json.dumps(value,ensure_ascii=False,indent=2)))
    add('public','公开角色资料','用户可见字段；不含提示词和私有设定。',public_profile(char))
    add('persona','完整角色设定','实际服务端角色源配置，含背景、性格、秘密、声线设计与说话习惯。',PROFILES[char])
    add('prompts','全部提示词','当前运行版本的原文，未摘要、未省略。',
        dict(planner=prompts.PLANNER,narrator=prompts.NARRATOR,structure=prompts.PLAN_SHAPE,reply_length=prompts.REPLY_LENGTH))
    add('context','本轮上下文预览','与生成共用上下文组装；只读，不发送、不扣费、不更新记忆。',context)
    add('memories','全部服务端记忆','本账号、本角色的全部记忆；本轮实际选中的记忆见上下文。',
        [dict(r) for r in store.db.execute('SELECT id,source,content,importance,created,recalled FROM memories WHERE owner=? AND character=? ORDER BY created',(owner,char))])
    add('client','本机发送内容','当前草稿及偏好、候选记忆、可用表现等请求正文。',request.model_dump(mode='json'))
    add('payload','完整规划请求预览','与实际 provider 共用构造函数；JSON Schema、system/user 消息及采样参数全部展开。',
        structured_payload(settings,'plan',structured_messages('plan',prompts.PLANNER,context,schemas.Plan)))
    add('schemas','全部生成结构约束','规划、旁白及客户端请求的完整 JSON Schema。',
        dict(plan=schemas.Plan.model_json_schema(),narration=schemas.NarrationResult.model_json_schema(),request=schemas.Request.model_json_schema()))
    add('performances','完整表演目录','实际可选资源、情绪映射所需意图、持续时间、冷却及可见效果。',assets(char))
    voice=store.get('voice','system',char,{})
    add('voice','语音与识别设定','完整音色设计在角色设定中；实际每次合成的文字、指令在请求记录中。',
        dict(active_voice={k:voice[k] for k in ('voice_id','revision','approved','model') if k in voice},
             emotion_tags=EMOTIONS,delivery_instructions=DELIVERY,vocal_tags=VOCALS,
             recognition_hotwords=PROFILES[char]['hotwords']+([request.preferences['nickname']] if request.preferences.get('nickname') else [])))
    fields=('character_model','tts_model','asr_model','narration_timeout_seconds','paid_enabled','enforce_conversation_limits',
            'max_daily_calls','max_daily_tts_characters','max_daily_asr_seconds','max_voice_designs','enable_test_inspector')
    add('models','模型与运行参数','凭证、认证头和本机文件路径不属于角色调教，不在报告中返回。',{k:getattr(settings,k) for k in fields})
    add('requests','最近实际请求','本账号、本角色最近 12 次 provider 请求正文，含格式修正；升级前未记录的请求不会伪造。',
        store.get('inspection_requests',owner,char,[]))
    # Runtime rules live in executable code as well as prompts. Include the full
    # deployed modules so a tester can inspect thresholds/filters without a
    # hand-maintained summary becoming a second, misleading source of truth.
    for name in ('prompts','schemas','greetings','director','speech_text','orchestrator','provider','asr','storage'):
        module=importlib.import_module('.'+name,__package__)
        add('rules-'+name,'执行规则 · '+name,'当前服务实际加载版本的完整规则源码。',Path(module.__file__).read_text())
    return dict(version=1,character_id=char,captured_at=datetime.now(timezone.utc).isoformat(),sections=sections)
