#!/usr/bin/env python3
from __future__ import annotations
import json, re, sys

def extract(raw: str):
    raw=raw.strip()
    if raw.startswith("```"):
        lines=raw.splitlines()
        if lines and lines[0].strip() in {"```","```json","```JSON"}:
            raw="\n".join(lines[1:-1] if lines[-1].strip()=="```" else lines[1:]).strip()
    try:
        obj=json.loads(raw)
        return obj if isinstance(obj,dict) else None
    except json.JSONDecodeError:
        pass
    dec=json.JSONDecoder(); found=[]
    for i,ch in enumerate(raw):
        if ch!="{": continue
        try: obj,end=dec.raw_decode(raw[i:])
        except json.JSONDecodeError: continue
        if isinstance(obj,dict): found.append((i,i+end,obj))
    maximal=[]
    for candidate in found:
        st,en,_=candidate
        if any(ost<=st and en<=oen and (ost,oen)!=(st,en) for ost,oen,_ in found): continue
        maximal.append(candidate)
    return maximal[0][2] if len(maximal)==1 else None

def nonempty(v): return isinstance(v,str) and bool(v.strip())
def strarr(v,minimum=0,maximum=20): return isinstance(v,list) and minimum<=len(v)<=maximum and all(nonempty(x) for x in v)
def risks(v): return isinstance(v,list) and len(v)<=20 and all(isinstance(x,dict) and set(x)=={"risk","mitigation"} and nonempty(x["risk"]) and nonempty(x["mitigation"]) for x in v)
def schema_version_valid(v): return not isinstance(v,bool) and isinstance(v,(int,float)) and v==1
def seat_valid(o):
    return isinstance(o,dict) and set(o)=={"schema_version","approach","dependencies","risks","testing","integration"} and schema_version_valid(o["schema_version"]) and strarr(o["approach"],1,5) and strarr(o["dependencies"]) and risks(o["risks"]) and strarr(o["testing"]) and strarr(o["integration"])
def synthesis_valid(o):
    required = {"schema_version", "conflicts", "gaps", "resolution", "risks", "decisions"}
    if not isinstance(o, dict) or set(o) - {"policy_findings"} != required:
        return False
    findings = o.get("policy_findings", [])
    return (
        schema_version_valid(o["schema_version"])
        and strarr(o["conflicts"]) and strarr(o["gaps"]) and nonempty(o["resolution"])
        and risks(o["risks"]) and strarr(o["decisions"])
        and isinstance(findings, list) and len(findings) <= 100
        and all(isinstance(finding, dict) for finding in findings)
    )
def compact(s): return re.sub(r"\s+"," ",s.strip())
def canonical(o):
    if isinstance(o,dict) and "schema_version" in o:
        o=dict(o)
        o["schema_version"]=1
    return json.dumps(o,ensure_ascii=False,separators=(",",":"))
def main():
    mode=sys.argv[1] if len(sys.argv)>1 else "seat"
    raw=sys.stdin.read()
    if mode=="wrap-seat":
        text=compact(raw)
        if not text: raise SystemExit(1)
        print(canonical({"schema_version":1,"approach":[text],"dependencies":[],"risks":[],"testing":[],"integration":[]})); return
    if mode=="wrap-synthesis":
        text=compact(raw)
        if not text: raise SystemExit(1)
        print(canonical({"schema_version":1,"conflicts":[],"gaps":[],"resolution":text,"risks":[],"decisions":[]})); return
    obj=extract(raw)
    if obj is None: raise SystemExit(1)
    if mode=="seat":
        if not seat_valid(obj): raise SystemExit(1)
        print(canonical(obj)); return
    if mode=="synthesis":
        if not synthesis_valid(obj): raise SystemExit(1)
        print(canonical(obj)); return
    if mode=="human-synthesis":
        if not synthesis_valid(obj): raise SystemExit(1)
        print("Resolution: "+compact(obj["resolution"]))
        for label,key in (("Conflicts","conflicts"),("Gaps","gaps"),("Decisions","decisions")):
            if obj[key]: print(label+": "+" | ".join(compact(x) for x in obj[key]))
        if obj["risks"]: print("Risks: "+" | ".join(compact(x["risk"])+" -> "+compact(x["mitigation"]) for x in obj["risks"]))
        return
    raise SystemExit(2)
if __name__=="__main__": main()
