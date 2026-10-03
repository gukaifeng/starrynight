#!/usr/bin/env python3
"""Compile reviewed host choreography. No models, inference or paid requests."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# id, label, official text tag, three distinct choreographies, authored intents
EMOTIONS=[
('neutral','自然','',('listening','understand','patient'),('neutral','thinking')),
('calm','平静','',('peaceful','patient','listening'),('neutral','soft_smile')),
('happy','开心','',('happy','welcome','admire'),('bright_smile','soft_smile','happy')),
('excited','兴奋','excited',('celebrate','delighted','reunion'),('bright_smile','happy','surprised')),
('sad','难过','sad',('sad','disappointed','miss_you'),('sad','worried')),
('crying','含泪','crying',('sad','apologize','worried'),('sad','worried')),
('angry','生气','angry',('pout','firm','disagree'),('pout','serious','angry')),
('worried','担心','',('worried','protect','empathetic'),('worried','sad','thinking')),
('fearful','不安','trembling',('worried','confused','protect'),('worried','surprised')),
('panicked','慌张','panicked',('surprised','worried','confused'),('surprised','worried')),
('surprised','惊讶','amazed',('surprised','delighted','idea'),('surprised','curious')),
('curious','好奇','curious',('curious','attentive','confused'),('curious','thinking')),
('thoughtful','思索','',('thinking','confused','explain'),('thinking','curious')),
('serious','认真','serious',('firm','explain','promise'),('serious','thinking')),
('empathetic','共情','empathetic',('empathetic','comfort','reassure'),('soft_smile','worried')),
('affectionate','亲近','',('affection','miss_you','admire'),('shy_smile','soft_smile')),
('shy','害羞','',('shy','hello_shy','grateful'),('shy_smile','soft_smile')),
('playful','俏皮','mischievously',('tease','proud','invite'),('teasing_smile','playful','bright_smile')),
('sarcastic','调侃','sarcastic',('tease','disagree','proud'),('teasing_smile','serious')),
('scornful','轻蔑','scornful',('firm','disagree','pout'),('serious','pout')),
('reluctant','不情愿','reluctantly',('disagree','pout','confused'),('pout','thinking')),
('bored','无聊','bored',('tired','peaceful','confused'),('neutral','thinking')),
('tired','疲惫','tired',('tired','sleepy','relieved'),('sad','neutral')),
('confident','自信','',('proud','promise','explain'),('bright_smile','serious')),
('grateful','感谢','',('grateful','admire','reassure'),('shy_smile','soft_smile')),
('jealous','吃醋','',('jealous','pout','shy'),('pout','shy_smile')),
('relieved','释然','',('relieved','peaceful','comfort'),('soft_smile','neutral')),
('hopeful','期待','',('encourage','invite','idea'),('bright_smile','curious')),
]
STYLES=[
('deep_shouting','深沉呐喊','deep and loud shouting',('firm','protect','celebrate'),('serious','surprised')),
('dracula','低沉阴森','like dracula',('firm','thinking','disagree'),('serious','thinking')),
('shouting','大声呼唤','shouting',('celebrate','protect','surprised'),('surprised','bright_smile')),
('asmr','轻柔气声','asmr',('peaceful','affection','attentive'),('soft_smile','shy_smile')),
('whisper','低声耳语','whispers',('shy','affection','listening'),('shy_smile','soft_smile')),
('slow','缓缓说','very slowly',('patient','thinking','reassure'),('thinking','soft_smile')),
('fast','轻快快语','very fast',('explain','delighted','tease'),('bright_smile','curious')),
]
VOCALS=[
('gasp','轻吸气','gasp',('surprised','confused','delighted'),('surprised',)),
('sigh','叹息','sighing',('relieved','tired','disappointed'),('sad','neutral')),
('throat_clear','清嗓','clears throat',('explain','firm','hello_shy'),('serious','shy_smile')),
('giggle','轻笑','giggles',('tease','shy','happy'),('teasing_smile','shy_smile','bright_smile')),
('laugh','开怀笑','laughing',('laugh','celebrate','delighted'),('bright_smile','happy')),
('cough','轻咳','cough',('worried','tired','apologize'),('worried','sad')),
('snort','轻哼','snorts',('pout','jealous','proud'),('pout','teasing_smile')),
]

def build():
    source=json.loads((ROOT/'unity/CharacterRuntime/Assets/Resources/HostEmotionGestures.json').read_text())
    bases={g['id']:g for g in source['gestures']}
    entries=[]
    for kind,definitions in [('emotion',EMOTIONS),('style',STYLES),('vocal',VOCALS)]:
        for key,label,tag,choreographies,intents in definitions:
            variants=[]
            for n,base in enumerate(choreographies,1):
                g=bases[base]
                variants.append(dict(id=f'{kind}.{key}.{n}',label=g['label'],base=base,
                    expression=g['expression'],secondary=g.get('secondary',''),
                    duration=g['duration'],finger=[1.8,2.8,2.2][n-1],stance=[.003,.004,.0025][n-1],
                    channels=['face','head','torso','shoulders','arms','wrists','fingers','hips','legs','feet','ears','tail','hair','clothing','accessories']))
            entries.append(dict(id=key,kind=kind,label=label,providerTag=tag,intents=list(intents),variants=variants))
    return dict(schemaVersion=1,revision=1,model='qwen-audio-3.1-tts-flash',
        source='https://help.aliyun.com/zh/model-studio/realtime-tts-user-guide',
        entries=entries,channelPolicy=dict(face='authored morph > nearest calibrated face > neutral',
            skeleton='calibrated humanoid additive; feet contacts preserved; author full pose wins',
            appendages='semantic authored cue > source spring inertia > explicit unavailable',
            timing='sentence PCM onset; vocal start offset; muted speech follows sentence timeline'))
if __name__=='__main__':
    target=ROOT/'unity/CharacterRuntime/Assets/Resources/EmotionPerformanceStandard.json'
    target.write_text(json.dumps(build(),ensure_ascii=False,indent=2)+'\n')
    print('42 controls, 126 variants:',target)
