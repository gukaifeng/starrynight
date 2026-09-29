"""Small persistent local deployment; SQLite WAL, transactions, owner/role scope."""
from pathlib import Path
from datetime import datetime, timezone
import sqlite3, json, time, math, hashlib

def dump(value): return json.dumps(value,ensure_ascii=False,separators=(',',':'))
def clamp(value): return min(1.,max(0.,value))

class Store:
    def __init__(self,path:Path):
        path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        self.db = sqlite3.connect(path,check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS records(kind TEXT,owner TEXT,character TEXT,data TEXT,updated REAL,PRIMARY KEY(kind,owner,character));
        CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,owner TEXT,character TEXT,request TEXT,role TEXT,data TEXT,created REAL);
        CREATE INDEX IF NOT EXISTS messages_scope ON messages(owner,character,created);
        CREATE TABLE IF NOT EXISTS requests(owner TEXT,character TEXT,id TEXT,payload_hash TEXT,status TEXT,result TEXT,created REAL,PRIMARY KEY(owner,character,id));
        CREATE TABLE IF NOT EXISTS memories(id TEXT,owner TEXT,character TEXT,source TEXT,content TEXT,importance REAL,created REAL,recalled REAL,PRIMARY KEY(owner,character,id));
        CREATE TABLE IF NOT EXISTS usage(id INTEGER PRIMARY KEY,kind TEXT,owner TEXT,character TEXT,reserved REAL,units REAL,status TEXT,metrics TEXT,created REAL);
        CREATE TABLE IF NOT EXISTS asset_usage(id INTEGER PRIMARY KEY,owner TEXT,character TEXT,asset TEXT,kind TEXT,created REAL);
        CREATE TABLE IF NOT EXISTS voice_design_jobs(id TEXT PRIMARY KEY,character TEXT,status TEXT,data TEXT,created REAL);
        ''')
        self.db.commit()

    def get(self,kind,owner,character,default=None):
        row=self.db.execute('SELECT data FROM records WHERE kind=? AND owner=? AND character=?',(kind,owner,character)).fetchone()
        return json.loads(row[0]) if row else default
    def put(self,kind,owner,character,value):
        with self.db:self.db.execute('INSERT OR REPLACE INTO records VALUES(?,?,?,?,?)',(kind,owner,character,dump(value),time.time()))
    def history(self,owner,character,limit=12):
        rows=self.db.execute('SELECT role,data FROM messages WHERE owner=? AND character=? ORDER BY created DESC LIMIT ?',(owner,character,limit)).fetchall()
        return [dict(role=r['role'],text=json.loads(r['data']).get('text','')[:700]) for r in reversed(rows)]
    def message(self,id,owner,character,request,role,data):
        with self.db:self.db.execute('INSERT OR IGNORE INTO messages VALUES(?,?,?,?,?,?,?)',(id,owner,character,request,role,dump(data),time.time()))
    def request(self,owner,character,id,payload):
        digest=hashlib.sha256(dump(payload).encode()).hexdigest()
        row=self.db.execute('SELECT * FROM requests WHERE owner=? AND character=? AND id=?',(owner,character,id)).fetchone()
        if row:
            if row['payload_hash']!=digest: raise ValueError('REQUEST_ID_REUSED')
            if row['result']:return json.loads(row['result'])
            raise ValueError('REQUEST_INCOMPLETE') # never automatically repeat a possibly billed call
        with self.db:self.db.execute('INSERT INTO requests VALUES(?,?,?,?,?,?,?)',(owner,character,id,digest,'running',None,time.time()))
        return None
    def complete(self,owner,character,id,result):
        with self.db:self.db.execute('UPDATE requests SET status=?,result=? WHERE owner=? AND character=? AND id=?',('completed',dump(result),owner,character,id))
    def sync_memories(self,owner,character,memories):
        with self.db:
            self.db.execute("DELETE FROM memories WHERE owner=? AND character=? AND source='manual'",(owner,character))
            for m in memories:self.db.execute('INSERT OR REPLACE INTO memories VALUES(?,?,?,?,?,?,?,?)',('manual:'+m.id,owner,character,'manual',m.text,.95,time.time(),0))
    def recall(self,owner,character,query):
        rows=self.db.execute('SELECT * FROM memories WHERE owner=? AND character=?',(owner,character)).fetchall()
        grams={query[i:i+2] for i in range(max(0,len(query)-1))}
        def score(r):
            overlap=sum(g in r['content'] for g in grams)/max(1,len(grams))
            return .65*overlap+.25*r['importance']+.1*math.exp(-(time.time()-r['created'])/2592000)
        chosen=sorted(rows,key=score,reverse=True)[:6]
        with self.db:
            for r in chosen:self.db.execute('UPDATE memories SET recalled=? WHERE owner=? AND character=? AND id=?',(time.time(),owner,character,r['id']))
        return [dict(type=r['source'],content=r['content']) for r in chosen]
    def state(self,owner,character):
        state=self.get('state',owner,character,dict(happiness=.45,sadness=.1,anger=0,anxiety=.1,loneliness=.1,energy=.65,boredom=.1,attention_to_user=.7,updated=time.time(),unanswered_proactive_count=0))
        dt=max(0,min(86400,time.time()-state.get('updated',time.time())))
        for key,base in [('happiness',.45),('sadness',.1),('anger',0),('anxiety',.1)]:
            state[key]=clamp(base+(state.get(key,base)-base)*math.exp(-dt/3600))
        state['boredom']=clamp(state.get('boredom',.1)+dt/7200)
        state['updated']=time.time()
        return state
    def reserve(self,kind,owner,character,units,settings):
        if not settings.paid_enabled: raise ValueError('PAID_CALLS_DISABLED')
        day=datetime.now(timezone.utc).strftime('%Y-%m-%d')
        start=datetime.strptime(day,'%Y-%m-%d').replace(tzinfo=timezone.utc).timestamp()
        with self.db:
            # Admission and reservation must be atomic even if a maintenance
            # process runs alongside the single-worker gateway.
            self.db.execute('BEGIN IMMEDIATE')
            used=self.db.execute("SELECT count(*) FROM usage WHERE created>=? AND status!='not_sent'",(start,)).fetchone()[0]
            if used>=settings.max_daily_calls:raise ValueError('DAILY_CALL_LIMIT')
            limit={'tts':settings.max_daily_tts_characters,'asr':settings.max_daily_asr_seconds,'voice_design':settings.max_voice_designs}.get(kind)
            if limit is not None:
                since=0 if kind=='voice_design' else start
                count=self.db.execute('SELECT coalesce(sum(reserved),0) FROM usage WHERE kind=? AND created>=?',(kind,since)).fetchone()[0]
                if count+units>limit:raise ValueError('USAGE_LIMIT_'+kind.upper())
            return self.db.execute('INSERT INTO usage(kind,owner,character,reserved,units,status,metrics,created) VALUES(?,?,?,?,?,?,?,?)',(kind,owner,character,units,0,'reserved','{}',time.time())).lastrowid
    def usage(self,id,status,metrics=None,units=None):
        with self.db:
            self.db.execute('UPDATE usage SET status=?,metrics=?,units=coalesce(?,units) WHERE id=?',(status,dump(metrics or {}),units,id))
            if status in ('completed','not_sent') and units is not None:self.db.execute('UPDATE usage SET reserved=? WHERE id=?',(units,id))
