"""Retain source-linked GitHub workflow job logs and conclusions."""
import argparse,hashlib,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--sha',required=True);p.add_argument('--prefix',required=True);a=p.parse_args()
e=pathlib.Path(__file__).resolve().parent
cmd=['gh','run','view',a.run,'--repo','gsmlg-dev/abyss','--json','databaseId,headSha,url,status,conclusion,jobs,name']
r=json.loads(subprocess.check_output(cmd,text=True));assert r['headSha']==a.sha,(r['headSha'],a.sha);assert r['status']=='completed',r['status']
for job in r['jobs']:
 log=e/f"{a.prefix}-job-{job['databaseId']}.log"
 data=subprocess.check_output(['gh','run','view',a.run,'--repo','gsmlg-dev/abyss','--job',str(job['databaseId']),'--log'])
 log.write_bytes(data);job['evidence_log']=log.name;job['sha256']=hashlib.sha256(data).hexdigest()
(e/f'{a.prefix}-results.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps({'run':a.run,'sha':r['headSha'],'conclusion':r['conclusion'],'jobs':len(r['jobs'])}))
