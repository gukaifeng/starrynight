#!/usr/bin/env python3
"""Reproducible MPFB -> skinned FBX with fitted morphs, using Blender's official bpy.

Run with .local/character-venv/bin/python. MPFB and downloaded source assets remain
outside the app. Only the dressed meshes, selected textures and credits are exported.
"""
from pathlib import Path
import os, sys, types, importlib.util, json, shutil, traceback

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.local/character-tools'
ASSETS = TOOLS / 'assets'
OUT = ROOT / 'unity/CharacterRuntime/Assets/ThirdParty/MakeHuman'
os.environ['BLENDER_USER_EXTENSIONS'] = str(TOOLS / 'blender-user')

def main():
    import bpy
    import numpy as np
    import addon_utils
    package = TOOLS / 'mpfb-package/mpfb'
    # MPFB is a Blender extension: importing it as a legacy "mpfb" addon is invalid.
    for name in ['bl_ext', 'bl_ext.xiaoban']:
        module = types.ModuleType(name); module.__path__ = [str(package.parent)]; sys.modules[name] = module
    name = 'bl_ext.xiaoban.mpfb'
    spec = importlib.util.spec_from_file_location(name, package/'__init__.py', submodule_search_locations=[str(package)])
    mpfb = importlib.util.module_from_spec(spec); sys.modules[name] = mpfb; spec.loader.exec_module(mpfb)
    bpy.context.preferences.addons.new().module = name
    mpfb.register()
    bpy.context.preferences.addons[name].preferences.mpfb_second_root = str(ASSETS)
    from bl_ext.xiaoban.mpfb.services.humanservice import HumanService
    from bl_ext.xiaoban.mpfb.services.targetservice import TargetService
    from bl_ext.xiaoban.mpfb.services.clothesservice import ClothesService
    from bl_ext.xiaoban.mpfb.services.objectservice import ObjectService
    from bl_ext.xiaoban.mpfb.entities.objectproperties import HumanObjectProperties
    from bl_ext.xiaoban.mpfb.entities.clothes.mhclo import Mhclo

    OUT.mkdir(parents=True, exist_ok=True)
    texture_dir = OUT / 'Textures'; texture_dir.mkdir(exist_ok=True)
    manifest = {'generator': {'bpy': bpy.app.version_string, 'mpfb': list(mpfb.VERSION), 'build': mpfb.BUILD_INFO},
                'character': 'fictional adult woman', 'materials': [], 'meshes': [], 'morphs': []}
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    macro = TargetService.get_default_macro_info_dict()
    # Gender 0 is female in macro.json; age .5 is the adult "young" basis, not child.
    macro.update(gender=0.0, age=.5, weight=.45, muscle=.35, height=.50, proportions=.52, cupsize=.42, firmness=.5)
    macro['race'] = {'asian': .72, 'caucasian': .28, 'african': 0}
    body = HumanService.create_human(macro_detail_dict=macro)
    body.name = 'SourceBody'
    target_dir = package / 'data/targets'
    def target(fragment, value):
        path = target_dir / (fragment+'.target.gz')
        if not path.exists(): raise RuntimeError('Target missing: '+str(path))
        key = TargetService.load_target(body,str(path),weight=value)
        return key
    target('head/head-oval',.12)
    target('chin/chin-width-decr',.08)
    target('expression/units/asian/mouth-corner-puller',.10)
    rig = HumanService.add_builtin_rig(body,'game_engine')
    rig.name = 'HumanRig'
    sources = [body]
    material_for = {}
    fittings = {}
    def material(name, path, transparent=False):
        info = {'name': name, 'alpha': transparent, 'source': str(path.relative_to(ASSETS)), 'textures': {}}
        for line in path.read_text().splitlines():
            parts = line.strip().split(None,1)
            if len(parts) != 2 or parts[0] not in ['diffuseTexture','normalmapTexture','specularTexture','aomapTexture']: continue
            source = path.parent / parts[1]
            if not source.is_file(): continue
            dest = texture_dir/(name+'_'+parts[0]+source.suffix)
            shutil.copy2(source,dest); info['textures'][parts[0]] = str(dest.relative_to(OUT))
        manifest['materials'].append(info)
        result = bpy.data.materials.new(name); result.diffuse_color = (.7,.7,.7,1); result.use_fake_user = True
        return result
    skin_path = ASSETS/'skins/onlytheghosts_young_eurasian_female/onlytheghosts_young_eurasian_female.mhmat'
    material_for[body.name] = material('RealSkin',skin_path)
    def asset(folder, filename, object_name, mat_name, asset_type='Clothes', subd=0, mat_file=None, alpha=False):
        path = ASSETS/folder/filename
        obj = HumanService.add_mhclo_asset(str(path),body,asset_type=asset_type,subdiv_levels=0,material_type='NONE',import_subrig=False,import_weights=False)
        obj.name = object_name
        fitting = Mhclo(); fitting.load(str(path)); fitting.clothes = obj; fittings[obj.name] = fitting
        if mat_file is None:
            entry = next(line.split(None,1)[1] for line in path.read_text().splitlines() if line.startswith('material '))
            mat_path = path.parent/entry
        else: mat_path = ASSETS/mat_file
        material_for[obj.name] = material(mat_name,mat_path,alpha)
        if subd:
            mod = obj.modifiers.new('Surface refinement','SUBSURF'); mod.levels = subd; mod.render_levels = subd
        sources.append(obj)
        return obj
    asset('eyes/high-poly','high-poly.mhclo','Eyes','RealEyes',asset_type='Eyes',mat_file='eyes/materials/brown.mhmat')
    asset('eyebrows/eyebrow008','eyebrow008.mhclo','Eyebrows','RealBrows',asset_type='Eyebrows',alpha=True)
    asset('eyelashes/eyelashes01','eyelashes01.mhclo','Eyelashes','RealLashes',asset_type='Eyelashes',alpha=True)
    asset('hair/elvs_daisy_hair','elvs_daisy_hair.mhclo','HairLong','RealHairLong',asset_type='Hair',alpha=True)
    asset('hair/elvs_short_side_do','elvs_short_side_do.mhclo','HairBob','RealHairBob',asset_type='Hair',alpha=True)
    asset('clothes/mindfront_knitted_sweater_01','mindfront_knitted_sweater_01.mhclo','Sweater','RealClothesKnit',subd=1)
    asset('clothes/toigo_wool_pants','toigo_wool_pants.mhclo','Trousers','RealTrousers',subd=1)
    asset('clothes/shoes02','shoes02.mhclo','Shoes','RealShoes')
    # Mask helpers and covered body regions BEFORE subdivision and morph snapshots.
    mod = body.modifiers.new('Skin refinement','SUBSURF'); mod.levels=1; mod.render_levels=1
    for obj in sources:
        for mod in obj.modifiers:
            if mod.type == 'ARMATURE': mod.show_viewport=False; mod.show_render=False
    def refit_assets():
        # Keep the skeleton's bind pose fixed for all variants. Refit garments/bodyparts only.
        bpy.context.view_layer.update()
        for obj in sources[1:]: ClothesService.fit_clothes_to_human(obj,body,fittings[obj.name],set_parent=False)
        bpy.context.view_layer.update()
    def snapshot():
        bpy.context.view_layer.update()
        graph = bpy.context.evaluated_depsgraph_get()
        return {o.name: bpy.data.meshes.new_from_object(o.evaluated_get(graph),preserve_all_data_layers=True,depsgraph=graph) for o in sources}
    def coordinates(mesh):
        a=np.empty(len(mesh.vertices)*3,dtype=np.float32);mesh.vertices.foreach_get('co',a);return a.reshape(-1,3)
    refit_assets(); basis=snapshot()
    poses={o.name:{} for o in sources}
    def remember(name):
        refit_assets(); meshes=snapshot()
        for obj in sources:
            m=meshes[obj.name]
            if len(m.vertices)!=len(basis[obj.name].vertices): raise RuntimeError('Morph topology changed: '+obj.name)
            poses[obj.name][name]=coordinates(m);bpy.data.meshes.remove(m)
        manifest['morphs'].append(name);print('Baked',name,flush=True)
    channels={
        'FaceWidth': [('head/head-scale-horiz',.23)],
        'JawShape': [('chin/chin-bones',.30),('chin/chin-width',.16)],
        'EyeSize': [('eyes/l-eye-scale',.18),('eyes/r-eye-scale',.18)],
        'MouthShape': [('mouth/mouth-lowerlip-volume',.28),('mouth/mouth-upperlip-volume',.28)],
        'NoseWidth': [('nose/nose-scale-horiz',.25)],
        'BodyCurve': [('hip/hip-scale-horiz',.24),('torso/measure-waist-circ',-.16)]}
    for channel,targets in channels.items():
        for suffix,side in [('Minus',-1),('Plus',1)]:
            keys=[]
            for fragment,amount in targets:
                full=fragment+('-incr' if amount*side>0 else '-decr')
                key=TargetService.load_target(body,str(target_dir/(full+'.target.gz')),weight=abs(amount))
                keys.append(key)
            remember(channel+suffix)
            for key in keys:
                if hasattr(key,'value'): key.value=0
                elif isinstance(key,str): body.data.shape_keys.key_blocks[key].value=0
                else: raise RuntimeError('Unexpected target key type '+str(type(key)))
    for label,value in [('Minus',.32),('Plus',.61)]:
        HumanObjectProperties.set_value('weight',value,entity_reference=body);TargetService.reapply_macro_details(body);remember('BodyBuild'+label)
    HumanObjectProperties.set_value('weight',.45,entity_reference=body);TargetService.reapply_macro_details(body)
    key=TargetService.load_target(body,str(target_dir/'expression/units/asian/mouth-open.target.gz'),weight=.65)
    remember('OpenMouth')
    if hasattr(key,'value'): key.value=0
    else: body.data.shape_keys.key_blocks[key].value=0
    blink_keys = [TargetService.load_target(body,str(target_dir/('expression/units/asian/eye-'+side+'-closure.target.gz')),weight=1) for side in ['left','right']]
    remember('Blink')
    for key in blink_keys: key.value=0
    refit_assets()
    # Split head and body from the SAME smooth surface. This preserves exact head hit testing.
    outputs=[]; bone_names=set(b.name for b in rig.data.bones)
    for source in sources:
        mesh=basis[source.name];base_co=coordinates(mesh)
        parts=['Head','Body'] if source==body else [source.name]
        for part in parts:
            polygons=[p for p in mesh.polygons if (part not in ['Head','Body'] or
                (min(base_co[v][2] for v in p.vertices)>1.25)==(part=='Head'))]
            used=sorted({v for p in polygons for v in p.vertices});lookup={v:i for i,v in enumerate(used)}
            data=bpy.data.meshes.new(part);data.from_pydata(base_co[used].tolist(),[],[[lookup[v] for v in p.vertices] for p in polygons]);data.update()
            obj=bpy.data.objects.new(part,data);bpy.context.collection.objects.link(obj);obj.matrix_world=source.matrix_world.copy();obj.parent=rig
            data.materials.append(material_for[source.name])
            if mesh.uv_layers.active:
                uv=data.uv_layers.new(name='UVMap')
                for new_p,old_p in zip(data.polygons,polygons):
                    for new_l,old_l in zip(new_p.loop_indices,old_p.loop_indices): uv.data[new_l].uv=mesh.uv_layers.active.data[old_l].uv
            for p in data.polygons:p.use_smooth=True
            data.normals_split_custom_set_from_vertices([tuple(mesh.vertices[v].normal) for v in used])
            groups={g.index:g.name for g in source.vertex_groups if g.name in bone_names}
            dest_groups={name:obj.vertex_groups.new(name=name) for name in groups.values()}
            for old,new in lookup.items():
                weights=sorted([(groups[g.group],g.weight) for g in mesh.vertices[old].groups if g.group in groups and g.weight>0.00001],key=lambda x:-x[1])[:4]
                total=sum(w for _,w in weights)
                if total<.00001: raise RuntimeError('Unweighted vertex in '+part)
                for n,w in weights:dest_groups[n].add([new],w/total,'REPLACE')
            obj.shape_key_add(name='Basis')
            for name,coords in poses[source.name].items():
                if np.max(np.abs(coords[used]-base_co[used]))<1e-7:continue
                key=obj.shape_key_add(name=name);key.data.foreach_set('co',coords[used].reshape(-1));key.value=0
            mod=obj.modifiers.new('Armature','ARMATURE');mod.object=rig
            outputs.append(obj)
            manifest['meshes'].append({'name':part,'vertices':len(data.vertices),'triangles':sum(len(p.vertices)-2 for p in data.polygons),'morphs':[k.name for k in obj.data.shape_keys.key_blocks][1:]})
    for obj in sources:bpy.data.objects.remove(obj,do_unlink=True)
    for mesh in basis.values():bpy.data.meshes.remove(mesh)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in outputs+[rig]:obj.select_set(True)
    bpy.context.view_layer.objects.active=rig
    addon_utils.enable('io_scene_fbx',default_set=False)
    bpy.ops.export_scene.fbx(filepath=str(OUT/'Xia.fbx'),use_selection=True,object_types={'ARMATURE','MESH'},
        use_mesh_modifiers=False,add_leaf_bones=False,bake_anim=False,path_mode='STRIP',axis_forward='-Z',axis_up='Y',
        apply_scale_options='FBX_SCALE_ALL',use_armature_deform_only=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(TOOLS/'Xia-source.blend'))
    (OUT/'character-source.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('CHARACTER_EXPORTED',manifest['meshes'],flush=True)

if __name__=='__main__':
    try:
        main();code=0
    except BaseException:
        traceback.print_exc();code=1
    # bpy's standalone macOS module may crash while tearing down registered extension
    # types. All artifacts are synchronously saved first; errors retain a nonzero code.
    sys.stdout.flush();sys.stderr.flush();os._exit(code)
