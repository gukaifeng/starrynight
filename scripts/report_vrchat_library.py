#!/usr/bin/env python3
"""Publish a compact inventory, never avatar curves, meshes, images or secrets.

The report distinguishes installed app capabilities from source-platform parity.
Private preflight evidence remains under .local and can be inspected separately.
"""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def main():
    folder=ROOT/'.local/vrchat-batch'
    plan=json.loads((folder/'plan.json').read_text())
    preflight={r['role']:r for r in json.loads((folder/'capability-preflight.json').read_text())['characters']}
    active=set(json.loads((ROOT/'assets/characters/active-roster.json').read_text())['characters'])
    special={
        'kumaly':'共享 dummy.anim 已从同作者 Ichigo 原包按 GUID/哈希找回；世界固定约束、原作物理开关及内置调试材质仍需适配，未激活。',
        'ramune':'完整根已找到；Modular Avatar 构建时控制器合并、原作粒子及约束尚未迁移，不能按零菜单模型发布。',
        'shizuku':'作者 lilToon 附加包与本体已合并；FBX 内嵌动画已恢复。LCDAnimShader / MIENAIPhotoUIShader 相机显示能力仍未适配。',
        'sio':'存在 FBX 内嵌材质，现有材质适配器尚未覆盖；另有原作 OutlineTex 引用待补，未激活。',
    }
    rows=[]
    for source in plan['models']:
        role=source['role'];check=preflight.get(role,{})
        unavailable=check.get('unavailableMotions',{})
        sdk=len(unavailable.get('officialSDK',[]));unknown=len(unavailable.get('unresolved',[]))
        path=folder/'converted'/role/'portable-conversion.json'
        material=json.loads(path.read_text()).get('materialLimitations',[]) if path.exists() else []
        problems=[]
        if sdk:problems.append(f'{sdk} 个可达 VRChat SDK 动作/树依赖未迁移')
        if unknown:problems.append(f'{unknown} 个可达动作引用未解析')
        textures={i['reference']['guid'] for i in material if i.get('reference',{}).get('guid')}
        shaders={i['sourceShader']['guid'] for i in material if i.get('sourceShader',{}).get('guid')}
        if textures:problems.append(f'{len(textures)} 个贴图引用待补齐')
        if shaders:problems.append(f'{len(shaders)} 类源 shader 未适配')
        needs={x['kind'] for x in check.get('sourceRequirements',[]) if x['kind'].startswith(('missing-','unsupported-','unknown-'))}
        if 'unsupported-build-merge-animator' in needs:problems.append('构建时控制器合并未适配')
        if 'unsupported-state-behaviour' in needs:problems.append('有待迁移的状态行为')
        if source['status']=='missing-avatar-prefab':status='缺本体，跳过';detail='只有龙胆的高尔夫服装包，不能生成完整角色。'
        elif role=='kipfel':status='保留旧版，升级待处理';detail='已安装 1.0.3；目录中的 1.1.1 尚未升级。'+'；'.join(problems)
        elif source['id'] in active:status='已加入 App';detail='角色包、专属产品内容及交互记录见批次报告；不代表 VRChat 全平台等价。'
        else:status='未激活';detail=special.get(role) or '；'.join(problems) or '仍需检查来源适配与渲染，未作为完整角色发布。'
        rows.append(dict(id=source['id'],sourceFolder=source['sourceFolder'],sourceVersion=source['version'],sourceSHA256=source['sourceSHA256'],
            status=status,controls=check.get('controls'),detail=detail))
    target=ROOT/'docs/verification/vrchat-batch-import/library-status.json'
    target.write_text(json.dumps(dict(schemaVersion=1,date='2026-10-01',sourceCount=len(rows),activeAppCount=len(active),
        scope='Audited source inventory; installed app interactions are not complete VRChat platform parity.',characters=rows),ensure_ascii=False,indent=2)+'\n')
    lines=['# 整库逐项结果（2026-10-01）','',
        '用户目录的 40 条来源都已完成档案审计。当前 App 名册以 `assets/characters/active-roster.json` 为准；豆日向来自此前的独立目录，不在这 40 条来源内。', '',
        '“已加入 App”包括角色会话、独立资料/媒体和已验证表现；不表示 VRChat 专用网络、世界约束、抓握和所有自定义 shader 都已等价移植。缺资源与宿主适配尚未完成分开记录，未激活项不会用另一角色的模型或声音冒充。', '',
        '| 来源目录 | 菜单/手势项 | 当前状态 | 依据 / 后续所需 |','| --- | ---: | --- | --- |']
    for row in rows:lines.append('| '+row['sourceFolder']+' | '+str(row['controls'] if row['controls'] is not None else '—')+' | '+row['status']+' | '+row['detail'].replace('|',' / ')+' |')
    lines+=['','平台动作引用可在官方 SDK 找到名称，不等于可以作为本 App 的通用素材发布；当前转换器保留缺口，不把缺失 motion 替换为空白。原始依赖 GUID、路径和归属的详细证据保存在 `.local/vrchat-batch/capability-preflight.json`、`archives/`、`stages/` 和转换日志。', '',
        '当前未完成的适配重点：Modular Avatar 的构建产物解析、原作粒子/世界约束、FBX 内嵌材质及角色专用屏幕 shader。官方 lilToon 工具贴图按固定源码哈希恢复，不归类为作者缺文件。', '']
    target.with_suffix('.md').write_text('\n'.join(lines))
    print('Library inventory:',len(rows),'sources;',len(active),'active app characters')

if __name__=='__main__':main()
