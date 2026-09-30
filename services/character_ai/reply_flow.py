"""Compile ordered speech/asides before publishing, using only resolved effects.

Parts are additive wire metadata; spoken dialogue remains the sole TTS input.
`at` is a fraction of spoken text, not a fabricated provider word timestamp.
"""
import re
from .schemas import visible_text, visible_thought

def duration_hint(text):
    cjk=len(re.findall(r'[\u3400-\u9fff]',text))
    if not cjk and re.search(r'[a-zA-Z]',text):return max(1.8,min(45,len(text.split())/2.6))
    return max(1.8,min(45,len(text)/5.5))

def boundary(text,fraction):
    if fraction<=0:return 0
    if len(text)<8:return len(text)
    points=[m.end() for m in re.finditer(r'[，。！？；、…～,.!?:;]',text)]
    # Keep a final thought after the last word; otherwise prefer phrase edges.
    internal=[p for p in points if 0<p<len(text)]
    target=round(len(text)*fraction)
    if not internal and re.search(r'[a-zA-Z]',text):internal=[m.end() for m in re.finditer(r'\s+',text)]
    return min(internal,key=lambda p:abs(p-target)) if internal else min(len(text),max(1,target))

def compile_parts(beat,resolved,language='zh'):
    text=visible_text(beat.dialogue.text) if beat.dialogue else ''
    size=max(1,len(text));markers=[];seen=set()
    thoughts=list(beat.asides)
    if not thoughts and beat.thought:
        thoughts=[beat.thought]
    for ordinal,thought in enumerate(thoughts):
        value=visible_thought(thought.text) if thought.visibility=='visible' else None
        anchor=getattr(thought,'after_text','')
        start=text.find(anchor) if anchor else 0
        if not value or value in seen:continue
        stage=getattr(thought,'stage','before')
        fraction={'before':0,'middle':(ordinal+1)/(len(thoughts)+1),'after':1}[stage]
        index=start+len(anchor) if anchor and start>=0 else (len(text) if fraction==1 else boundary(text,fraction))
        # Keep trailing punctuation with its spoken clause, never strand a
        # comma on a separate line between two neighbouring annotations.
        while index>0 and index<len(text) and text[index] in '，。！？；、…～,!?:;':index+=1
        markers.append((index,'thought',value));seen.add(value)
    # Select one genuine observation at onset and one at the later phase.
    # Do not duplicate every simultaneous hand/ear/tail cue in the transcript.
    cues=[c for c in resolved['performances'] if c['active'] and c['asset'].get('observable_effects')] if language!='en' else []
    phases=[sorted([c for c in cues if c['offset_ms']<1200],key=lambda c:(c['asset']['group']!='expression',c['offset_ms'])),
            sorted([c for c in cues if c['offset_ms']>=1200],key=lambda c:c['offset_ms'])]
    for phase in phases:
        for cue in phase:
            value=visible_text(cue['asset']['observable_effects'][0])
            if value in seen:continue
            fraction=min(.8,cue['offset_ms']/1000/duration_hint(text)) if text else 0
            markers.append((boundary(text,fraction),'narration',value));seen.add(value);break
    parts=[];cursor=0
    for index,kind,value in sorted(markers,key=lambda m:m[0]):
        if index>cursor:
            parts.append(dict(kind='dialogue',text=text[cursor:index],at=round(cursor/size,4)))
            cursor=index
        parts.append(dict(kind=kind,text=value,at=round(index/size,4)))
    if cursor<len(text):parts.append(dict(kind='dialogue',text=text[cursor:],at=round(cursor/size,4)))
    return parts
