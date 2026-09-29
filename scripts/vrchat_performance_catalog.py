"""Verified source-animation inventory and data-only performance recipes.

Uses the archived SHA-256 audit and relocation resolver; never executes source code.
Weights retain Unity's 0..100 units. Bone animation is separately sampled by Unity.
"""
import json
import re
from collections import Counter
from pathlib import Path
from vrchat_source_paths import resolve_source_path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / 'docs/verification/vrchat-import/source-audit.json'
GROUP_LABELS = {'expression':'表情','pose':'姿态与动作','hands':'手势','ears':'耳朵','tail':'尾巴','appearance':'穿搭配件'}
LABELS = {
'default':'自然神态','default 1':'自然神态一','default 2':'自然神态二','default 3':'自然神态三','default 4':'自然神态四',
'niyari':'俏皮一笑','wink':'眨眼','smile':'微笑','he':'微张嘴','he(LipSyncOFF)':'微张嘴（固定嘴型）','pero2':'吐舌二','confidence':'自信','confidence2':'自信二','cry':'哭泣','akubi':'打哈欠','cheek':'鼓起脸颊','pale':'脸色发白','nagomi':'安心','cateye2':'猫眼二','ho':'轻轻惊叹','cry2':'含泪','doubt':'疑惑','doya':'得意','sleep':'熟睡表情','whiteeye':'白眼','angry':'生气','wink2':'眨眼二','guruguru':'晕乎乎','nya':'猫咪表情','flehmen':'呆住','happy':'被摸头的开心','hunt':'认真盯住','cateye':'猫眼','catsmile':'猫咪微笑','pero':'吐舌','happy2':'开心二','muu':'嘟嘴','kirakira':'闪亮眼睛','kirakira2':'闪亮眼睛二','unhappy':'被摸头的不满','blackeye':'黑眼','yummy':'好吃','drool':'流口水','musu':'闹别扭','garuru':'龇牙','hukure':'鼓脸','exciting':'兴奋','donbiki':'震惊','anger':'生气','bigsmile':'灿烂笑容','sweat':'紧张冒汗','hunsu':'哼一声','perori':'舔嘴角','surprise':'惊讶','cry_hau':'委屈','hatena':'疑问','hoo':'惊叹','wink_kira':'闪亮眨眼',
'hand_idle':'放松双手','hands_idle':'放松双手','fist':'握拳','open':'张开手掌','point':'指向','peace':'剪刀手','rock':'摇滚手势','gun':'手指枪','thumbs_up':'点赞',
'stand_still':'自然站姿','stand':'自然站姿','crouch_still':'蹲姿','prone01_still':'俯卧一','prone02_still':'俯卧二','sit':'坐姿','fall_short':'下落姿态','breath':'轻轻呼吸','afk_stand_to_sleep':'躺下入睡','afk_sleep_loop':'安静睡眠','afk_sleep_to_stand':'睡醒起身',
'idle':'自然状态','up':'竖起','down':'垂下','pyoko_loop':'耳朵轻动','pyoko_right':'右耳轻动','pyoko_left':'左耳轻动','active':'展开耳朵','inactive':'收起耳朵','puff':'蓬起尾巴','roll':'卷起尾巴','upwag':'竖起摇尾','updown':'轻摆尾巴','downwag':'低垂摇尾','pyoko':'耳朵轻动','default-dog':'自然耳尾',
'Cap':'帽子','Bag':'挎包','Vest':'背心','Shirt':'衬衫','Shorts':'短裤','Boots':'靴子','Socks':'袜子','Glasses':'眼镜','BodyBag':'斜挎包','DogCollar':'项圈','SunVisor':'遮阳帽','Yakke':'外套','Shoes':'鞋子','Shirt_sleeve':'短袖样式'
}

def yaml_field(block,key,default=''):
    m=re.search(r'^[ \t]*'+re.escape(key)+r':[ \t]*(.*?)[ \t]*$',block,re.M)
    value=m.group(1) if m else default
    if value.startswith(chr(34)) and value.endswith(chr(34)):
        return json.loads(value)
    if value.startswith(chr(39)) and value.endswith(chr(39)):
        return value[1:-1].replace(chr(39)*2,chr(39))
    return value

def source_text(asset):
    return resolve_source_path(asset['extractedPath'], expected_sha256=asset['sha256']).read_text(encoding='utf-8-sig')

def float_curves(text):
    m=re.search(r'^  m_FloatCurves:(.*?)(?=^  m_PPtrCurves:)',text,re.M|re.S)
    if not m:return []
    result=[]
    for block in re.split(r'^  - (?=serializedVersion:|curve:)',m.group(1),flags=re.M)[1:]:
        keys=[]
        for t,v in re.findall(r'^        time: ([^\n]+)\n        value: ([^\n]+)',block,re.M):
            try:keys.append({'time':float(t),'value':float(v)})
            except ValueError:continue
        result.append({'path':yaml_field(block,'path'),'attribute':yaml_field(block,'attribute'),'classID':int(yaml_field(block,'classID','0')),'keys':keys})
    return result

def classify(path):
    p=path.lower()
    if '/option/' in p or '/facialcontrol/' in p or Path(path).stem.startswith('_'):return 'internal'
    if '/outfit/' in p or '/anim_costume/' in p:return 'appearance'
    if '/facial/' in p or '/anim_facial/' in p:return 'expression'
    if 'catear_' in p or 'dogear_' in p:return 'ears'
    if 'cattail_' in p or 'dogtail_' in p:return 'tail'
    if 'dog_default' in p:return 'ears'
    if '/handgesture/' in p:return 'hands'
    if any(p.endswith('_'+s+'.anim') for s in ['gun','fist','open','point','peace','rock','thumbs_up','hands_idle']):return 'hands'
    return 'pose'

def inventory(role):
    audit=json.loads(AUDIT.read_text())
    archive=next(x for x in audit['archives'] if x['slug'].startswith(role))
    assets=[z for p in archive['unityPackages'] if 'quest' not in p['file'].lower() for z in p['assets']]
    result=[]
    for asset in sorted(assets,key=lambda x:x['path']):
        if asset['extension']!='.anim':continue
        a=asset['animation']; text=source_text(asset); curves=float_curves(text)
        morphs=[{'renderer':c['path'],'shape':c['attribute'][11:],'weight':c['keys'][-1]['value']} for c in curves if c['attribute'].startswith('blendShape.') and c['keys']]
        visibility=[{'path':c['path'],'visible':c['keys'][-1]['value']>=0.5} for c in curves if c['attribute']=='m_IsActive' and c['keys'] and c['classID']==1]
        result.append({'guid':asset['guid'],'path':asset['path'],'sha256':asset['sha256'],'name':a['clipName'],'group':classify(asset['path']),'duration':a['stopTime'],'loop':a['loop'],'classification':a['classification'],'floatCurves':curves,'morphs':morphs,'visibility':visibility})
    return result

def label(clip):
    name=clip['name']; s=name
    for prefix in ['kipfel_facial_','kipfel_hand_','kipfel_CatEar_','kipfel_CatTail_','kipfel_','Mamehinata_','DogEar_','DogTail_','F_','Pet_']:
        if s.startswith(prefix):s=s[len(prefix):];break
    if name=='kipfel_hand_idle':s='hand_idle'
    if name=='Dog_Default':s='default-dog'
    return LABELS.get(s,LABELS.get(s.lower(),s))

def identifier(name):return re.sub(r'[^a-z0-9]+','-',name.lower()).strip('-')

def build_character(role):
    clips=inventory(role); by_name={x['name']:x for x in clips}; options=[]; omitted=[]; consumed=set()
    for c in clips:
        if c['path'] in consumed:continue
        group=c['group']
        if group=='internal':
            omitted.append({'sourceClip':c['path'],'reason':'VRChat 内部眨眼/口型/碰撞/自触碰控制或空片段，不是独立可见表演'});continue
        if group=='appearance':
            n=c['name']; prefix='kipfel_outfit_' if role=='kipfel' else 'C_';stem=n[len(prefix):]
            if stem in ['Shirt_OFF','Shirt_ON','Shorts_OFF','Shorts_ON','Yakke_OFF','Yakke_ON']:
                omitted.append({'sourceClip':c['path'],'reason':'保留基础上装与短裤；移除可能露出身体，不开放脱除'});continue
            if stem.startswith('Shirt_sleeve_'):
                if stem.endswith('_long'):continue
                off=by_name['kipfel_outfit_Shirt_sleeve_long']; base='Shirt_sleeve'; on=c; default=False
            else:
                if stem.endswith('_OFF'):continue
                if not stem.endswith('_ON'):
                    omitted.append({'sourceClip':c['path'],'reason':'没有经过核验的开关配对'});continue
                base=stem[:-3]; off=by_name.get(n[:-3]+'_OFF'); on=c; default=base!='Glasses'
                if not off:
                    omitted.append({'sourceClip':c['path'],'reason':'来源缺少 OFF 配对'});continue
            consumed.add(off['path'])
            options.append({'id':'outfit-'+identifier(base),'group':group,'label':LABELS.get(base,base),'kind':'toggle','clip':'','sourceClip':on['path'],'sourceOffClip':off['path'],'description':'原模型穿搭开关；保留基础上装与短裤','duration':on['duration'],'loop':False,'bones':[],'morphs':on['morphs'],'visibility':on['visibility'],'offMorphs':off['morphs'],'offVisibility':off['visibility'],'defaultOn':default})
            continue
        option={'id':identifier(c['name']),'group':group,'label':label(c),'kind':'motion' if c['duration']>0 else 'preset','clip':'','sourceClip':c['path'],'description':'原作连续表演' if c['duration']>0 else '原作静态姿态或表情，通过平滑过渡呈现','duration':c['duration'],'loop':c['loop'],'bones':[],'morphs':c['morphs'],'visibility':c['visibility'],'offMorphs':[],'offVisibility':[],'defaultOn':False}
        option['sourceMorphCurves']=[{'renderer':f['path'],'shape':f['attribute'][11:],'keys':f['keys']} for f in c['floatCurves'] if f['attribute'].startswith('blendShape.')]
        if c['name'].endswith('_breath'):option['additive']=True
        # Cat ears are disabled in author's default outfit, but explicit ear motions need visibility.
        if role=='kipfel' and group=='ears' and not c['name'].endswith('_inactive'):
            option['visibility']=[*option['visibility'],{'path':'Cat_Ear','visible':True}]
        options.append(option)
    groups=[{'id':g,'label':l} for g,l in GROUP_LABELS.items() if any(o['group']==g for o in options)]
    accounted={o['sourceClip'] for o in options}|{o['sourceOffClip'] for o in options if o.get('sourceOffClip')}|{o['sourceClip'] for o in omitted}
    missing=[c['path'] for c in clips if c['path'] not in accounted]
    if missing:raise ValueError('Unaccounted clips: '+str(missing))
    return {'role':role,'performance':{'schemaVersion':1,'defaults':[],'groups':groups,'options':options},'coverage':{'sourceClipCount':len(clips),'zeroDurationClipCount':sum(c['duration']==0 for c in clips),'optionCount':len(options),'optionsByGroup':dict(Counter(o['group'] for o in options)),'omitted':omitted,'accountedSourceClips':len(accounted)}}

def write_catalog(path=None):
    path=Path(path or ROOT/'docs/verification/vrchat-performance/catalog.json');path.parent.mkdir(parents=True,exist_ok=True)
    report={'schemaVersion':1,'source':'SHA-256 verified source YAML, not runtime acceptance','characters':[build_character(r) for r in ['kipfel','mamehinata']]}
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');return report

if __name__=='__main__':
    x=write_catalog()
    for c in x['characters']:print(c['role'],c['coverage'])
