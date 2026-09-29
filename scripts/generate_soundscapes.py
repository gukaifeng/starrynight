#!/usr/bin/env python3
"""Author role-specific sample-free circular scores; bundle lossless CAF/ALAC.
Uses existing .local/character-venv numpy and macOS afconvert, with no downloads.
Run --catalog-only after regenerating characters to restore their audio metadata.
Use --only ROLE [ROLE ...] to generate selected roles and preserve other assets.
"""
import argparse
import hashlib
import json
import subprocess
import struct
import wave
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'ios/CharacterHost/Resources'
WORK = ROOT / '.local/checks/character-music'
AUDIT = ROOT / 'docs/verification/character-music/audio-audit.json'
RATE = 32000
SCALES = {'major':[0,2,4,5,7,9,11], 'minor':[0,2,3,5,7,8,10], 'lydian':[0,2,4,6,7,9,11]}
# Legacy option suffixes stay unchanged. Every score has its own melody,
# harmony, rhythm, tempo and instrument recipe, not a renamed shared recording.
SCORES = {
 'real-woman':[
  ('breeze','窗边暖茶','柔和钢琴 · 温暖从容','sun.haze',48,'major',76,'felt',[0,5,3,4,2,5,1,4],[9,8,6,7,5,4,8,7]),
  ('sea','海风来信','轻拨弦 · 平静海风','water.waves',53,'major',72,'pluck',[0,3,5,1,3,0,2,4],[7,9,8,5,6,8,4,7])],
 'studio-robot':[
  ('orbit','慢慢绕着你','柔光合成器 · 安静轨道','circle.dotted',45,'minor',80,'warm',[0,3,5,6,0,5,3,4],[7,4,6,9,8,5,3,7]),
  ('light','口袋里的光','电子木琴 · 轻巧明亮','sun.max',50,'lydian',90,'wood',[0,1,4,2,5,0,3,4],[7,10,9,5,8,11,9,7])],
 'hatsune-miku':[
  ('night','薄荷色晚星','清透钟音 · 轻盈夜色','moon.stars',50,'major',78,'glass',[0,4,5,3,1,5,2,4],[11,9,7,8,10,6,9,7]),
  ('day','小小的开场','柔和电钢 · 明亮节拍','music.note',55,'lydian',96,'bell',[0,2,1,4,5,3,0,4],[7,9,11,10,8,12,9,8])],
 'sample-robot':[
  ('walk','陪你走一小段','木琴拨弦 · 轻松散步','leaf',55,'major',88,'wood',[0,3,1,4,2,5,3,0],[7,8,10,9,5,8,6,7]),
  ('rest','小院灯还亮','圆润钟音 · 安心停靠','moon',48,'major',74,'bell',[5,3,0,4,1,5,2,0],[9,7,5,6,8,4,7,5])],
 'anime-vita':[
  ('moon','银叶微光','毡音钢琴 · 沉静月色','moon.stars',51,'major',70,'felt',[0,5,2,3,1,4,5,0],[7,5,9,8,4,6,8,7]),
  ('breeze','轻轻醒来','木质拨弦 · 清晨舒展','wind',46,'major',84,'pluck',[0,1,5,4,3,2,1,0],[8,10,7,9,6,4,5,7])],
 'anime-shino':[
  ('moon','花影慢慢','柔软钟音 · 温柔花影','moon.stars',53,'lydian',72,'bell',[0,2,5,3,1,0,4,2],[9,7,10,8,6,9,5,7]),
  ('breeze','今天也有微风','木琴与弦 · 自在日常','wind',48,'major',82,'wood',[3,0,1,5,2,4,0,3],[7,9,6,8,10,7,4,6])],
 'anime-fumiriya':[
  ('moon','庭院里的信','温暖电钢 · 安静相伴','moon.stars',47,'minor',74,'warm',[0,5,3,6,2,4,5,0],[8,6,7,10,9,5,4,7]),
  ('breeze','叶间小路','柔和拨弦 · 午后闲步','wind',52,'major',86,'pluck',[0,3,2,5,4,1,3,0],[7,11,9,8,5,7,10,6])],
 'anime-uka':[
  ('moon','留一盏小灯','玻璃琴音 · 安静守候','moon.stars',53,'major',68,'glass',[0,5,1,3,2,4,5,0],[10,8,7,5,9,6,8,7]),
  ('breeze','心事晒一晒','木质拨弦 · 轻柔晴日','sun.haze',48,'lydian',80,'pluck',[0,2,4,1,5,3,2,0],[7,10,8,11,9,6,5,8])],
 'anime-velara':[
  ('moon','绒雪与晚星','轻柔竖琴音 · 梦境微光','moon.stars',56,'major',70,'pluck',[0,5,3,2,1,4,2,0],[9,11,8,7,10,6,9,7]),
  ('breeze','晨光在肩上','暖色钢琴 · 从容清晨','sun.max',51,'lydian',78,'felt',[3,0,2,4,1,5,0,3],[8,7,10,9,5,8,11,7])],
 'anime-onyx':[
  ('moon','夜色慢半拍','低柔电钢 · 平静夜话','moon',47,'minor',66,'warm',[0,3,6,5,2,0,4,5],[7,9,6,8,4,7,10,5]),
  ('breeze','云边停一会儿','圆润木琴 · 轻松留白','cloud',50,'major',82,'wood',[5,1,3,0,2,4,1,0],[9,7,8,11,6,10,5,7])],
 'anime-kipfel':[
  ('moon','月亮藏在口袋里','玻璃琴音 · 轻软晚安','moon.stars',54,'lydian',73,'glass',[0,1,5,2,4,0,3,5],[10,7,9,12,8,6,10,7]),
  ('breeze','花园里的小步子','圆润木琴 · 轻盈散步','leaf',49,'major',87,'wood',[0,4,1,5,3,2,0,4],[8,11,7,10,9,5,8,6])],
 'anime-mamehinata':[
  ('moon','把晚风留给你','毡音钢琴 · 温柔低语','moon',46,'major',69,'felt',[3,5,0,2,1,4,3,0],[9,6,8,10,7,5,9,8]),
  ('breeze','窗台上的晴天','柔和拨弦 · 暖光日常','sun.max',54,'lydian',83,'pluck',[0,2,5,1,4,3,1,0],[7,10,12,8,11,7,9,6])]
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def decoded_pcm(path):
    # afconvert writes WAVE_FORMAT_EXTENSIBLE (PCM subtype), which Python 3.11's
    # wave reader cannot open. Read its bounded RIFF chunks without a new decoder.
    data=path.read_bytes(); assert data[:4]==b'RIFF' and data[8:12]==b'WAVE'
    offset=12; pcm=None; valid=False
    while offset+8<=len(data):
        kind=data[offset:offset+4]; length=struct.unpack_from('<I',data,offset+4)[0]
        chunk=data[offset+8:offset+8+length]; assert len(chunk)==length
        if kind==b'fmt ':
            tag,channels,rate,_,_,bits=struct.unpack_from('<HHIIHH',chunk)
            valid=channels==2 and rate==RATE and bits==16 and (tag==1 or (tag==65534 and chunk[24:40]==bytes.fromhex('0100000000001000800000aa00389b71')))
        if kind==b'data': pcm=chunk
        offset+=8+length+(length%2)
    assert valid and pcm is not None,'Unexpected decoded PCM format'
    return pcm

def synthesize(role, index, recipe):
    suffix,title,detail,symbol,tonic,mode,bpm,instrument,harmony,melody = recipe
    beat=60/bpm; frames=round(32*beat*RATE)
    mix=np.zeros((frames,2),np.float64); scale=SCALES[mode]; events=[]
    def pitch(degree): return tonic+12*(degree//7)+scale[degree%7]
    def note(midi,start,length,gain,pan,voice):
        count=round(length*RATE); t=np.arange(count)/RATE; hz=440*2**((midi-69)/12)
        attack=.6 if voice=='pad' else .032 if voice=='felt' else .018
        decay=4.5 if voice=='pad' else 1.55 if voice in ('warm','glass') else 1.0
        rise=np.sin(np.pi*.5*np.minimum(t/attack,1))**2
        release=np.sin(np.pi*.5*np.minimum((length-t)/.65,1))**2
        envelope=rise*release*np.exp(-t/decay); phase=2*np.pi*hz*t
        if voice=='pad': sound=np.sin(phase)+.16*np.sin(phase*1.0015)+.045*np.sin(phase*2)
        elif voice=='bell': sound=np.sin(phase+.30*np.exp(-t/.20)*np.sin(phase*2))+.065*np.sin(phase*3)*np.exp(-t/.4)
        elif voice=='glass': sound=np.sin(phase)+.13*np.sin(phase*2)*np.exp(-t/.8)+.04*np.sin(phase*4)*np.exp(-t/.3)
        elif voice=='pluck': sound=sum(np.sin(phase*h)/h**2.35*np.exp(-t*(h-1)/2) for h in range(1,6))
        elif voice=='wood': sound=np.sin(phase)+.16*np.sin(phase*2)*np.exp(-t/.22)
        elif voice=='warm': sound=np.sin(phase+.11*np.sin(phase*2)*np.exp(-t/.6))+.06*np.sin(phase*3)
        else: sound=np.sin(phase)+.12*np.sin(phase*2)*np.exp(-t/.8)+.04*np.sin(phase*3)*np.exp(-t/.35)
        signal=sound*envelope*gain
        stereo=signal[:,None]*np.array([np.cos((pan+1)*np.pi/4),np.sin((pan+1)*np.pi/4)])
        offset=round(start*RATE)%frames; first=min(count,frames-offset)
        mix[offset:offset+first]+=stereo[:first]
        if first<count: mix[:count-first]+=stereo[first:]
        events.append([midi,round(start,6),round(length,6),voice])
    rhythm=[0,1.25,2.5,3.25] if index else [.25,1.5,2.25,3.5]
    for bar,degree in enumerate(harmony):
        start=bar*4*beat
        for i,step in enumerate([0,2,4,6]): note(pitch(degree+step)-12,start+i*.041,beat*9,.026,-.35+i*.22,'pad')
        note(pitch(degree)-12,start+beat*.08,beat*3.8,.026,0,'warm')
        for i,when in enumerate(rhythm):
            step=[0,4,2,6][(i+bar+index)%4]
            note(pitch(degree+step)+12,start+when*beat,beat*3.7,.035 if index==0 else .043,-.30 if i%2==0 else .30,instrument)
        note(pitch(melody[bar]),start+beat*(1 if index else .75),beat*4.5,.060,.09,instrument)
        if bar%2==index: note(pitch(melody[(bar+3)%8]),start+beat*3,beat*4,.042,-.12,instrument)
    dry=mix.copy()
    for delay,gain in [(.137,.13),(.293,.10),(.467,.07),(.733,.055),(1.071,.035)]: mix+=np.roll(dry,round(delay*RATE),axis=0)[:,::-1]*gain
    mix-=mix.mean(axis=0); mix=np.tanh(mix*1.6); mix-=mix.mean(axis=0)
    mix*=min(.075/np.sqrt(np.mean(mix**2)),.46/np.abs(mix).max())
    # Circular voices/reverb already preserve complete tails. Pick a quiet,
    # low-derivative start without fading every loop into an artificial silence.
    steps=np.max(np.abs(mix-np.roll(mix,1,axis=0)),axis=1)
    split=int(np.argmin(steps+np.max(np.abs(mix),axis=1)*.002)); mix=np.roll(mix,-split,axis=0)
    pcm=np.round(mix*32767).astype('<i2')
    asset='Music_'+role.replace('-','_')+'_'+suffix
    WORK.mkdir(parents=True,exist_ok=True); wav=WORK/(asset+'.wav')
    with wave.open(str(wav),'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(RATE); f.writeframes(pcm.tobytes())
    caf=OUT/(asset+'.caf')
    subprocess.run(['/usr/bin/afconvert','-f','caff','-d','alac',str(wav),str(caf)],check=True,capture_output=True)
    decoded=WORK/(asset+'-decoded.wav')
    subprocess.run(['/usr/bin/afconvert','-f','WAVE','-d','LEI16',str(caf),str(decoded)],check=True,capture_output=True)
    assert decoded_pcm(decoded)==pcm.tobytes(),'Lossless roundtrip or loop frame count changed'
    normalized=pcm.astype(np.float64)/32768
    report=dict(id=role+'/'+suffix,sourceModelID=role,asset=asset,assetExtension='caf',title=title,detail=detail,symbol=symbol,
        duration=frames/RATE,sha256=digest(caf),bytes=caf.stat().st_size,sampleRate=RATE,channels=2,bits=16,codec='Apple Lossless',
        bpm=bpm,instrument=instrument,tonic=tonic,mode=mode,harmony=harmony,melody=melody,
        scoreSha256=hashlib.sha256(json.dumps(events).encode()).hexdigest(),pcmSha256=hashlib.sha256(pcm.tobytes()).hexdigest(),
        peak=float(np.abs(normalized).max()),rms=float(np.sqrt(np.mean(normalized**2))),dc=float(np.abs(normalized.mean(axis=0)).max()),
        seamStep=float(np.abs(normalized[-1]-normalized[0]).max()),
        seamSlopeStep=float(np.abs((normalized[1]-normalized[0])-(normalized[0]-normalized[-1])).max()),
        roundtripPCMIdentical=True,loopFrames=frames)
    assert report['peak']<.461 and .055<report['rms']<.08
    assert report['dc']<.00002 and report['seamStep']<.002 and report['seamSlopeStep']<.003
    return report

def synchronize_collection_music(report=None, roles=None):
    report=report or json.loads(AUDIT.read_text()); tracks={t['id']:t for t in report['tracks']}
    path=OUT/'CharacterCollections.json'; catalog=json.loads(path.read_text())
    fields=['id','asset','assetExtension','sourceModelID','sha256','duration','title','detail','symbol']
    for collection in catalog['collections']:
        if roles is not None and collection['modelID'] not in roles:
            continue
        for i,old in enumerate(collection['music']):
            if old['id'] in tracks: collection['music'][i]={key:tracks[old['id']][key] for key in fields}
        collection['version']='1.1.0'
    path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog-only',action='store_true')
    parser.add_argument('--only',nargs='+',choices=list(SCORES),metavar='ROLE',
                        help='Regenerate only these roles, retaining the other audited CAF assets unchanged')
    args=parser.parse_args()
    selected=set(args.only) if args.only else set(SCORES)
    if args.catalog_only:
        synchronize_collection_music(roles=selected if args.only else None)
        return
    tracks=[]
    expected={role+'/'+recipe[0] for role,recipes in SCORES.items() for recipe in recipes}
    if args.only:
        previous=json.loads(AUDIT.read_text())
        tracks=[track for track in previous['tracks'] if track['sourceModelID'] not in selected]
        retained={track['id'] for track in tracks}
        needed={role+'/'+recipe[0] for role,recipes in SCORES.items() if role not in selected for recipe in recipes}
        assert retained==needed, 'Unselected roles need complete existing audio evidence; include missing roles in --only'
        # Fail before synthesizing anything if a retained recording was changed
        # or removed. Selected imports must never bless stale audio evidence.
        for track in tracks:
            assert digest(OUT/(track['asset']+'.caf'))==track['sha256'], 'Retained CAF differs from audit: '+track['id']
    for role,recipes in SCORES.items():
        if role not in selected:
            continue
        for index,recipe in enumerate(recipes):
            tracks.append(synthesize(role,index,recipe)); print('Composed '+tracks[-1]['id'],flush=True)
    assert {track['id'] for track in tracks}==expected, 'Audio recipes and evidence differ'
    for field in ['id','asset','sha256','pcmSha256','scoreSha256']:
        assert len({t[field] for t in tracks})==len(expected),'Shared music content: '+field
    report=dict(schemaVersion=1,authorship='Project-original algorithmic scores and synthesized instruments. No third-party samples, recordings or copied score.',
        license='LicenseRef-ProjectOriginal',generator='scripts/generate_soundscapes.py',distinctScores=len(tracks),distinctPCM=len(tracks),
        totalBundledBytes=sum(t['bytes'] for t in tracks),tracks=tracks)
    AUDIT.parent.mkdir(parents=True,exist_ok=True); AUDIT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    synchronize_collection_music(report,roles=selected)
    print(f"PASS: {len(tracks)} distinct lossless loops; {report['totalBundledBytes']/1_000_000:.2f} MB bundled")

if __name__=='__main__': main()
