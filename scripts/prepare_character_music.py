#!/usr/bin/env python3
"""One role-owned track, from reviewed CC0 sources or completed Bailian receipts.
Sources remain intact; derivatives are gain-normalized, crossfaded and ALAC coded.
"""
import argparse,hashlib,json,subprocess,urllib.request,wave
from pathlib import Path
import numpy as np
from generate_soundscapes import decoded_pcm

ROOT=Path(__file__).resolve().parents[1]
RATE=32000
def digest(data):return hashlib.sha256(data).hexdigest()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--ai',action='store_true',help='Require completed Fun-Music outputs instead of CC0 interim tracks')
    args=parser.parse_args()
    catalog=json.loads((ROOT/'assets/characters/music-sources.json').read_text())
    recipes={r['id']:r for r in json.loads((ROOT/'assets/characters/media-recipes.json').read_text())['characters']}
    work=ROOT/'.local/character-media/music';work.mkdir(parents=True,exist_ok=True)
    resources=ROOT/'ios/CharacterHost/Resources';tracks=[];credits=[]
    for entry in catalog['tracks']:
        role=entry['role'];target=work/(role+Path(entry['download']).suffix)
        if args.ai:
            target=ROOT/'.local/character-media'/role/'music.wav'
            receipt=json.loads(target.with_suffix('.json').read_text())
            assert receipt['status']=='complete' and digest(target.read_bytes())==receipt['sha256']
            provenance=dict(kind='bailian-generated',model=receipt['model'],requestID=receipt['requestID'])
        else:
            if not target.exists():
                with urllib.request.urlopen(entry['download'],timeout=90) as response:
                    payload=response.read(120_000_001)
                    assert len(payload)<120_000_000,'Audio exceeds download limit'
                    target.write_bytes(payload)
            provenance={k:entry[k] for k in ('originalTitle','author','license','licenseURL','source')};provenance['kind']='licensed-interim'
        # 120s cap controls bundled size; preserve the original source locally.
        raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(target),'-t','120','-f','f32le','-ar',str(RATE),'-ac','2','-'])
        pcm=np.frombuffer(raw,dtype='<f4').reshape(-1,2).astype(np.float64)
        assert len(pcm)>RATE*5 and np.isfinite(pcm).all(),'Invalid/short music'
        overlap=min(RATE*2,len(pcm)//8)
        ramp=(.5-.5*np.cos(np.linspace(0,np.pi,overlap)))[:,None]
        pcm[-overlap:]=pcm[-overlap:]*(1-ramp)+pcm[:overlap]*ramp
        pcm=pcm[overlap:]
        # Place the cyclic seam at a quiet, smooth point of the continuous
        # waveform. A large adjacent sample slope isn't an audible gap, but a
        # low-slope cut also protects players that reset interpolation on loop.
        step=np.max(np.abs(pcm-np.roll(pcm,1,axis=0)),axis=1)
        slope=np.max(np.abs(np.roll(pcm,-1,axis=0)-2*pcm+np.roll(pcm,1,axis=0)),axis=1)
        split=int(np.argmin(step+slope+np.max(np.abs(pcm),axis=1)*.002))
        pcm=np.roll(pcm,-split,axis=0);pcm-=pcm.mean(axis=0)
        gain=min(.065/np.sqrt(np.mean(pcm**2)),.44/np.abs(pcm).max());pcm*=gain
        encoded=np.round(pcm*32767).astype('<i2');data=encoded.tobytes()
        asset='Music_'+role.replace('-','_')+'_theme';wav=work/(asset+'.wav');caf=resources/(asset+'.caf')
        with wave.open(str(wav),'wb') as file:
            file.setnchannels(2);file.setsampwidth(2);file.setframerate(RATE);file.writeframes(data)
        subprocess.run(['/usr/bin/afconvert','-f','caff','-d','alac',str(wav),str(caf)],check=True,capture_output=True)
        decoded=work/(asset+'-decoded.wav')
        subprocess.run(['/usr/bin/afconvert','-f','WAVE','-d','LEI16',str(caf),str(decoded)],check=True,capture_output=True)
        assert decoded_pcm(decoded)==data,'ALAC must round-trip exactly'
        signal=encoded.astype(np.float64)/32768
        track=dict(id=role+'/theme',sourceModelID=role,asset=asset,assetExtension='caf',title=recipes[role]['title'] if args.ai else entry['title'],detail=entry['detail'],symbol='music.note',
            sha256=digest(caf.read_bytes()),bytes=caf.stat().st_size,duration=len(encoded)/RATE,sampleRate=RATE,channels=2,bits=16,codec='Apple Lossless',
            pcmSha256=digest(data),scoreSha256=digest(target.read_bytes()),sourceSHA256=digest(target.read_bytes()),provenance=provenance,
            peak=float(np.abs(signal).max()),rms=float(np.sqrt(np.mean(signal**2))),dc=float(np.abs(signal.mean(axis=0)).max()),
            seamStep=float(np.abs(signal[-1]-signal[0]).max()),seamSlopeStep=float(np.abs((signal[1]-signal[0])-(signal[0]-signal[-1])).max()),roundtripPCMIdentical=True)
        tracks.append(track)
        credits.append(role+' · '+track['title']+'\n'+json.dumps(provenance,ensure_ascii=False,indent=2)+'\n处理：选段、循环交叉淡化、响度调整、转码。')
        print(role,round(track['duration'],2),'seconds',round(track['rms'],4),'rms',round(track['seamStep'],6),'seam',flush=True)
    report=dict(schemaVersion=2,authorship='Bailian AI music' if args.ai else 'Reviewed third-party CC0 recordings; temporary user-approved selection, not project AI output.',tracks=tracks)
    audit=ROOT/'docs/verification/character-music/audio-audit.json';audit.parent.mkdir(parents=True,exist_ok=True);audit.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    path=resources/'CharacterCollections.json';collections=json.loads(path.read_text());by_role={t['sourceModelID']:t for t in tracks}
    fields=['id','asset','assetExtension','sourceModelID','sha256','duration','title','detail','symbol']
    for collection in collections['collections']:
        track=by_role[collection['modelID']];collection['music']=[{k:track[k] for k in fields}];collection['defaultMusic']=track['id'];collection['version']='1.2.0'
    path.write_text(json.dumps(collections,ensure_ascii=False,indent=2)+'\n')
    (resources/'MusicCredits.txt').write_text('\n\n'.join(credits)+'\n')
if __name__=='__main__':main()
