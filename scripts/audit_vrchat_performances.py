#!/usr/bin/env python3
"""Audit avatar menus, controller bindings and raw animation/shape capabilities.

Run with .local/character-sdk-venv/bin/python (PyYAML safe loader). Reads only
SHA-verified extracted assets. No avatar C#/SDK/custom editor execution.
"""
import argparse
import json
import re
from collections import Counter
from pathlib import Path
import yaml
from vrchat_performance_catalog import ROOT, AUDIT, build_character, inventory, source_text


def unity_documents(text):
    """Discard Unity type tags without permitting YAML object constructors."""
    records=[]
    for match in re.finditer(r'^--- !u!(\d+) &(-?\d+)(?: stripped)?\n(.*?)(?=^--- !u!|\Z)',text,re.M|re.S):
        value=yaml.safe_load(match.group(3))
        if isinstance(value,dict):
            records.append({'classID':int(match.group(1)),'fileID':int(match.group(2)),**value})
    return records


def audit_controller(asset, by_guid):
    docs=unity_documents(source_text(asset)); by_id={d['fileID']:d for d in docs}; states=[]; transitions=[]
    def motions(ref,seen=None):
        seen=set() if seen is None else seen
        if not isinstance(ref,dict):return []
        guid=ref.get('guid')
        if guid:
            target=by_guid.get(guid)
            return [{'guid':guid,'fileID':ref.get('fileID'),'path':target['path'] if target else None,'external':target is None}]
        fid=ref.get('fileID',0)
        if not fid or fid in seen:return []
        seen.add(fid); d=by_id.get(fid,{})
        tree=d.get('BlendTree',{})
        return [v for c in tree.get('m_Childs',[]) for v in motions(c.get('m_Motion'),seen.copy())]
    for d in docs:
        if 'AnimatorState' in d:
            s=d['AnimatorState']; states.append({'fileID':d['fileID'],'name':s.get('m_Name'),'motions':motions(s.get('m_Motion')),'writeDefaults':s.get('m_WriteDefaultValues'),'speed':s.get('m_Speed'),'transitions':[r.get('fileID') for r in s.get('m_Transitions',[])]})
        if 'AnimatorStateTransition' in d:
            t=d['AnimatorStateTransition'];transitions.append({'fileID':d['fileID'],'destination':t.get('m_DstState',{}).get('fileID'),'conditions':t.get('m_Conditions',[]),'duration':t.get('m_TransitionDuration'),'hasExitTime':t.get('m_HasExitTime'),'exitTime':t.get('m_ExitTime')})
    animator=next((d['AnimatorController'] for d in docs if 'AnimatorController' in d),{})
    layers=[{'name':x.get('m_Name'),'stateMachine':x.get('m_StateMachine',{}).get('fileID'),'defaultWeight':x.get('m_DefaultWeight')} for x in animator.get('m_AnimatorLayers',[])]
    return {'path':asset['path'],'guid':asset['guid'],'parameters':animator.get('m_AnimatorParameters',[]),'layers':layers,'states':states,'transitions':transitions}


def audit_role(role, archive):
    assets=[a for p in archive['unityPackages'] if 'quest' not in p['file'].lower() for a in p['assets']]
    by_guid={a['guid']:a for a in assets}; menus=[]; parameters=[]
    controllers=[audit_controller(a,by_guid) for a in assets if a['extension']=='.controller']
    for asset in assets:
        if asset['extension']!='.asset':continue
        docs=unity_documents(source_text(asset))
        if not docs:continue
        data=docs[0].get('MonoBehaviour',{})
        if 'parameters' in data:parameters.append({'path':asset['path'],'parameters':data['parameters']})
        if 'controls' not in data:continue
        controls=[]
        for c in data['controls']:
            parameter=(c.get('parameter') or {}).get('name') or ''
            submenu=by_guid.get((c.get('subMenu') or {}).get('guid'),{})
            associations=[]
            for controller in controllers:
                states={s['fileID']:s for s in controller['states']}
                matches=[{'conditions':t['conditions'],'destination':states.get(t['destination'])} for t in controller['transitions'] if any(x.get('m_ConditionEvent')==parameter for x in t['conditions']) and parameter]
                if matches:associations.append({'controller':controller['path'],'transitions':matches})
            controls.append({'name':c.get('name'),'type':c.get('type'),'typeName':{101:'button',102:'toggle',103:'submenu',104:'two-axis',105:'four-axis',106:'radial'}.get(c.get('type'),'unknown'),'parameter':parameter,'value':c.get('value'),'submenu':submenu.get('path'),'subParameters':c.get('subParameters',[]),'controllerAssociations':associations,'portability':'VRChat SDK builtin emote, source motion is external' if parameter=='VRCEmote' else 'interaction mode; reimplement with App touch inputs' if parameter=='PetMode' else 'submenu' if c.get('type')==103 else 'local appearance switch'})
        menus.append({'path':asset['path'],'guid':asset['guid'],'name':data.get('m_Name'),'controls':controls})
    prefab=json.loads((ROOT/f'.local/vrchat-stage/Inspection/{role}-prefab.json').read_text())
    fbx=json.loads((ROOT/f'.local/vrchat-stage/Inspection/{role}-fbx.json').read_text())
    skins=[]
    for s in prefab['skins']:
        skins.append({k:s[k] for k in ['path','active','enabled','mesh','vertices','triangles','shapes','weights']})
    catalog=build_character(role)
    clips=inventory(role)
    for c in clips:
        dynamic=[f for f in c['floatCurves'] if len({k['value'] for k in f['keys']})>1]
        c['dynamicFloatCurveCount']=len(dynamic)
        c['staticTimeline']=c['duration']==0
    external=sorted({m['guid'] for c in controllers for s in c['states'] for m in s['motions'] if m['external']})
    primitive=[a for a in assets if a['extension']=='.fbx']
    return {'role':role,'archiveSHA256':archive['archiveSHA256'],'sourceClipCount':len(clips),'sourceClips':clips,'menus':menus,'expressionParameters':parameters,'controllers':controllers,'externalControllerMotionGUIDs':external,'renderers':skins,'hiddenNodes':[{'path':n['path'],'active':n['active']} for n in prefab['nodes'] if not n['active']],'fbxAssets':[{'path':a['path'],'sha256':a['sha256'],'boneCount':a['fbx']['boneCount'],'blendShapeChannelCount':a['fbx']['blendShapeChannelCount'],'blendShapeNames':a['fbx']['blendShapeNames'],'animationStacks':a['fbx']['animationStacks']} for a in primitive],'coverage':catalog['coverage'],'optionSourceMappings':[{k:o[k] for k in ['id','group','label','kind','sourceClip','sourceOffClip'] if k in o} for o in catalog['performance']['options']]}


def markdown(data):
    lines=['# VRChat 原作表现与菜单审计','', '本报告只声明来源能力与可转换目录；实际 App 是否可见、动作是否正确，以最终运行验收为准。静态姿势、服饰开关、零秒表情不计作长动画。','', '来源文件通过原审计 SHA-256 校验后读取。Unity YAML 仅使用安全数据解析；没有执行来源脚本。菜单控制条件列为原控制器关联，不声称已经完整模拟 VRChat Animator 图。','']
    for role in data['characters']:
        cov=role['coverage']; lines += [f"## {role['role']}",'',f"{cov['sourceClipCount']} 个源片段，其中 {cov['zeroDurationClipCount']} 个零秒片段。目录 {cov['optionCount']} 项；分类 {json.dumps(cov['optionsByGroup'],ensure_ascii=False)}。所有源片段均计入保留/配对/省略记录。",'','### 原菜单','', '| 菜单 | 选项 | 参数 / 值 | 迁移属性 |','|---|---|---|---|']
        for m in role['menus']:
            for c in m['controls']:
                lines.append(f"| {m['name']} | {c['name']} | `{c['parameter']}` / {c['value']} | {c['portability']} |")
        lines += ['','### 表现目录','', '| 分组 | 中文名称 | 源片段 | 种类 |','|---|---|---|---|']
        for o in role['optionSourceMappings']:lines.append(f"| {o['group']} | {o['label']} | `{Path(o['sourceClip']).name}` | {o['kind']} |")
        lines += ['','### 未开放 / 内部控制','']
        for o in cov['omitted']:lines.append(f"- `{Path(o['sourceClip']).name}`：{o['reason']}。")
        lines += ['','### 原模型形变与默认可见性','', '| Renderer | 默认激活 | Renderer 开关 | 原形变数量 |','|---|---|---|---|']
        for s in role['renderers']:lines.append(f"| `{s['path']}` | {s['active']} | {s['enabled']} | {len(s['shapes'])} |")
        lines += ['', '全部形变名称、原始权重、每个浮点关键帧、控制器状态/转换、外部 GUID 见同目录 `source-capabilities.json`。', '']
    lines += ['## 明确边界','', '- Wave、Clap、Point、Cheer、Dance、Backflip、SadKick、Die 是两个菜单均引用的 VRCEmote 项，不能仅凭菜单存在就称原作者已提供这些身体动作。动作控制器引用的外部 GUID 已逐个列出。','- PetMode 是关闭/开心/不满的触碰响应模式，原作对应表情可迁移，网络 Contacts 和他人手部输入需要 App 语义重建。','- 上装、短裤 OFF 不开放；其来源仍完整列入覆盖记录。配件开关不等于完整捏人编辑器。','- Mamehinata 的 SunVisor / NameTag 是额外 Prefab/FBX，不能假定主 FBX 已包含；以最终转换的绑定检查结果为准。','- 原动画 YAML 两种列表格式（带 serializedVersion 与直接 curve）及带 Unicode 转义的日文形变都已解析。动态表情时序位于 sourceMorphCurves，末帧不能代替整个表演。','']
    return '\n'.join(lines)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'docs/verification/vrchat-performance/source-capabilities.json');args=parser.parse_args()
    audit=json.loads(AUDIT.read_text());data={'schemaVersion':1,'auditTool':'scripts/audit_vrchat_performances.py','characters':[audit_role(role,next(a for a in audit['archives'] if a['slug'].startswith(role))) for role in ['kipfel','mamehinata']]}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');args.output.with_suffix('.md').write_text(markdown(data))
    print(json.dumps({'characters':[{'role':c['role'],'clips':len(c['sourceClips']),'menus':len(c['menus']),'controllers':len(c['controllers']),'externalMotionGUIDs':len(c['externalControllerMotionGUIDs'])} for c in data['characters']]},ensure_ascii=False))

if __name__=='__main__':main()
