#!/usr/bin/env python3
"""Build private immutable OSS artifacts from reviewed prefabs and existing media.

No AI calls. Source packages stay untouched. Run after both platform bundle builds.
The plan is consumed by the server repository's official OSS SDK publisher.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import uuid
import zipfile

ROOT=Path(__file__).resolve().parents[1]
RES=ROOT/'ios/StarryNight/Resources'
def read(path):return json.loads(path.read_text())
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        while data:=f.read(1024*1024):h.update(data)
    return h.hexdigest()
def artwork(asset):
    folders=list((ROOT/'ios/StarryNight').rglob(f'{asset}.imageset'))
    if len(folders)!=1:raise ValueError('Artwork catalog is missing or ambiguous: '+asset)
    folder=folders[0]
    names=[i['filename'] for i in read(folder/'Contents.json')['images'] if i.get('filename')]
    if not names:raise ValueError('Missing artwork: '+asset)
    return folder/names[0]
def build(version):
    policy=read(ROOT/'assets/characters/delivery-policy.json')
    catalog=read(RES/'CharacterCatalog.json')['characters']
    covers={c['runtimeID']:c for c in read(RES/'CharacterCoverCatalog.json')['covers']}
    openings={c['characterID']:c for c in read(RES/'CharacterOpenings.json')['characters']}
    collections={c['modelID']:c for c in read(RES/'CharacterCollections.json')['collections']}
    profiles={c['id']:c for c in read(RES/'CharacterPublicProfiles.json')['characters']}
    atmospheres={c['id']:c for c in read(RES/'CharacterAtmospheres.json')['characters']}
    if version<=0:raise ValueError('Release version must be positive')
    out=ROOT/'.local/character-delivery'/str(version)
    if (out/'publish-plan.json').exists():raise ValueError('This version already has an immutable publication plan. Reuse that plan or choose a new version.')
    out.mkdir(parents=True,exist_ok=True)
    objects=[];listings=[];releases=[]
    def obj(file,key,content_type):
        entry=dict(local=str(file),key=key,size=file.stat().st_size,sha256=digest(file),content_type=content_type)
        objects.append(entry);return dict(path=file.name,object_key=key,size=entry['size'],sha256=entry['sha256'],content_type=content_type)
    for model in catalog:
        role=model['id'];folder=out/role;folder.mkdir(exist_ok=True)
        media={}
        for kind,asset in [('cover',covers[role]['asset']),('avatar',covers[role].get('avatar',covers[role]['asset']))]:
            src=artwork(asset);dest=folder/(kind+src.suffix);shutil.copy2(src,dest)
            media[kind]=obj(dest,f'characters/{role}/previews/{digest(dest)}/{dest.name}','image/png' if dest.suffix=='.png' else 'image/jpeg')
        opening=openings[role]['variants'][0]
        audition=folder/'audition.m4a'
        subprocess.run(['ffmpeg','-v','error','-y','-f','s16le','-ar','24000','-ac','1','-i',str(RES/(opening['audio']+'.pcm')),'-c:a','aac','-b:a','96k',str(audition)],check=True)
        media['audition']=obj(audition,f'characters/{role}/previews/{digest(audition)}/audition.m4a','audio/mp4')
        remote=role in policy['downloadOnly']
        listings.append(dict(id=role,name=model['display']['name'],description=model['display']['description'],delivery='oss' if remote else 'bundled',media=media,
            data={'descriptor':model,'collection':collections[role],'public_profile':profiles[role],'cover_layout':covers[role],'audition_text':opening['text']}))
        if not remote:continue
        source_files={'media/'+(opening['audio']+'.pcm'):RES/(opening['audio']+'.pcm')}
        for item in openings[role]['variants']+openings[role].get('legacyVariants',[]):source_files['media/'+item['audio']+'.pcm']=RES/(item['audio']+'.pcm')
        for track in collections[role]['music']:source_files['media/'+track['asset']+'.'+track.get('assetExtension','wav')]=RES/(track['asset']+'.'+track.get('assetExtension','wav'))
        metadata={'descriptor':model,'collection':collections[role],'opening':openings[role],'atmosphere':atmospheres[role],'public_profile':profiles[role]}
        meta=folder/'character.json';meta.write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n');source_files['metadata/character.json']=meta
        for kind in ['cover','avatar']:source_files['media/'+media[kind]['path']]=folder/media[kind]['path']
        for name in ['LICENSE.txt','NOTICE.md']:
            src=ROOT/'character-packages/imported'/role/name
            if src.exists():source_files['licenses/'+name]=src
        for platform in ['ios','ios-simulator']:
            bundle=ROOT/'.local/character-delivery/bundles'/platform/(role+'.bundle')
            files=source_files|{'runtime/character.bundle':bundle}
            members=[dict(path=path,size=file.stat().st_size,sha256=digest(file)) for path,file in sorted(files.items())]
            header=dict(schemaVersion=1,characterID=role,version=version,platform=platform,runtimeVersion=policy['runtimeVersion'],unityVersion='6000.3.25f1',bundle='runtime/character.bundle',bundleCRC=int(bundle.with_suffix('.bundle.crc').read_text()),files=members)
            target=folder/(platform+'.character.zip')
            with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_STORED,allowZip64=True) as z:
                z.writestr('package.json',json.dumps(header,ensure_ascii=False))
                for path,file in sorted(files.items()):z.write(file,path)
            key=f'characters/{role}/releases/{version}/{platform}/{digest(target)}/character.zip'
            entry=obj(target,key,'application/zip')
            release=dict(schema_version=1,character_id=role,release_id=str(uuid.uuid5(uuid.NAMESPACE_URL,key)),version=version,platform=platform,runtime_version=policy['runtimeVersion'],files=[dict(path='character.zip',object_key=key,size=entry['size'],sha256=entry['sha256'])],extensions={'archive':'starry-character-zip/1','audience':'private-development','expanded_bytes':sum(m['size'] for m in members)})
            releases.append(release)
    plan=dict(audience='private-development',objects=objects,listings=listings,releases=releases)
    (out/'publish-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'roles':len(listings),'remote_roles':policy['downloadOnly'],'releases':len(releases),'objects':len(objects),'plan':str(out/'publish-plan.json')},ensure_ascii=False))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--version',type=int,default=1);args=p.parse_args();build(args.version)
