import copy,importlib.util,json,os,subprocess,sys
from pathlib import Path
P=Path(__file__).parents[2]/'model-development'/'benchmark'/'run_daily_benchmark.py';S=importlib.util.spec_from_file_location('daily_benchmark',P);daily=importlib.util.module_from_spec(S);S.loader.exec_module(daily)
sys.path.insert(0,str(P.parent))
def test_manifest_schedule():
 m=daily.load_manifest(daily.DEFAULT_MANIFEST);assert [x.get('n') for x in m['days'][:4]]==[64,64,32,500];assert m['defaults']['preflight_n']==5
def test_command_is_strict(tmp_path):
 m=daily.load_manifest(daily.DEFAULT_MANIFEST);c=daily.public_command(m['days'][0],m['defaults'],5,tmp_path/'r.json');assert c[c.index('--n')+1]=='5';assert c[c.index('--profile')+1]=='public_cag_compare';assert '--no-allow-fallback' in c;assert '--no-allow-degraded-provider' in c
 stage=daily.build_plan(m['days'][0],m,tmp_path/'day-01')[0]
 assert stage['environment']['TRACECAG_USE_LEARNED_RANKER']=='false'
 assert stage['environment']['TRACECAG_BENCHMARK_FAIL_FAST']=='true'
 assert stage['environment']['TRACECAG_BENCHMARK_FAIL_ON_PROVIDER_ERROR']=='true'
def test_report_requires_passed_true(tmp_path):
 p=tmp_path/'r.json';p.write_text(json.dumps({'run_validation':{'passed':True}}));stage={'validator':'public','outputs':[p]};assert daily.valid_output(stage);p.write_text('{}');assert not daily.valid_output(stage)

def test_resume_rejects_stale_or_mismatched_public_report(tmp_path):
 m=daily.load_manifest(daily.DEFAULT_MANIFEST)
 stage=daily.build_plan(m['days'][0],m,tmp_path/'day-01')[0]
 p=stage['outputs'][0];p.parent.mkdir(parents=True)
 expected=stage['expected_public']
 report={
  'run_validation':{'passed':True},
  'dataset':{'name':expected['dataset'],'sha256':expected['dataset_sha256']},
  'configuration':{key:expected[key] for key in ('provider','model','seed','cache_repeats','generation_policy','evidence_mode','implementation_sha256')},
  'summaries':{mode:{} for mode in expected['modes']},
  'kg_preflight':{'source_sha256':expected['kg_sha256']},
  'kg_runtime_provenance':{
   'source_unchanged':True,'working_copy_isolated':True,
   'working_copy_pre_sha256':expected['kg_sha256'],
   'working_copy_path_distinct':True,'working_copy_writable':True,
  },
  'observations':[{} for _ in range(expected['observations'])],
 'suite_id':expected['suite_id'],'stage_id':expected['stage_id'],
 }
 p.write_text(json.dumps(report));assert daily.valid_output(stage)
 mutations=(
  lambda value:value['configuration'].__setitem__('seed',7),
  lambda value:value['configuration'].__setitem__('implementation_sha256','0'*64),
  lambda value:value['configuration'].pop('implementation_sha256'),
  lambda value:value['dataset'].__setitem__('sha256','0'*64),
 lambda value:value['kg_preflight'].__setitem__('source_sha256','0'*64),
  lambda value:value['kg_runtime_provenance'].__setitem__('source_unchanged',False),
  lambda value:value['kg_runtime_provenance'].__setitem__('working_copy_isolated',False),
  lambda value:value['kg_runtime_provenance'].pop('working_copy_isolated'),
  lambda value:value['observations'].pop(),
  lambda value:value['summaries'].pop('tracecag_rapid'),
  lambda value:value.__setitem__('suite_id','stale-suite'),
  lambda value:value.__setitem__('stage_id','full'),
 )
 for mutate in mutations:
  stale=copy.deepcopy(report);mutate(stale);p.write_text(json.dumps(stale));assert not daily.valid_output(stage)

def test_days_five_to_seven_are_executable(tmp_path):
 m=daily.load_manifest(daily.DEFAULT_MANIFEST)
 day5=daily.build_plan(m['days'][4],m,tmp_path/'day-05',output_root=tmp_path)
 assert [s['name'] for s in day5]==['full_tracecag']
 assert any('clusters_test.jsonl' in item for item in day5[0]['command'])
 day6=daily.build_plan(m['days'][5],m,tmp_path/'day-06',output_root=tmp_path)
 assert 'embedding_preflight' in [s['name'] for s in day6]
 assert day6[-1]['optional_gate']=='embedding'
 day7=daily.build_plan(m['days'][6],m,tmp_path/'day-07',output_root=tmp_path)
 assert [s['name'] for s in day7]==['threshold_sensitivity','collect_results','aggregate_tables']

def test_manifest_rejects_non_consecutive_days(tmp_path):
 p=tmp_path/'manifest.json';p.write_text(json.dumps({'schema_version':1,'days':[{'day':2}]}))
 try:daily.load_manifest(p)
 except ValueError as exc:assert 'consecutive days' in str(exc)
 else:raise AssertionError('invalid schedule was accepted')

def test_next_day_is_locked_until_previous_day_passes(tmp_path):
 result=subprocess.run([sys.executable,str(P),'--day','2','--output-dir',str(tmp_path),'--dry-run'],capture_output=True,text=True)
 assert result.returncode==4
 assert 'locked' in result.stderr.lower()

def test_next_day_dry_run_unlocks_after_previous_pass(tmp_path):
 previous=daily.status_path(tmp_path,1);previous.parent.mkdir(parents=True);previous.write_text(json.dumps({'status':'passed'}))
 result=subprocess.run([sys.executable,str(P),'--day','2','--output-dir',str(tmp_path),'--dry-run'],capture_output=True,text=True)
 assert result.returncode==0
 commands=json.loads(result.stdout)
 assert commands['preflight'][commands['preflight'].index('--n')+1]=='5'
 assert commands['full'][commands['full'].index('--n')+1]=='64'

def test_run_stage_carries_progress_identity(tmp_path, monkeypatch):
 captured={}
 class Result:returncode=0
 def fake_run(command, **kwargs):captured.update(kwargs);return Result()
 monkeypatch.setattr(daily.subprocess,'run',fake_run)
 daily.run_stage({'name':'full','command':['benchmark'],'outputs':[],'validator':'exit','environment':{'KUZU_DB_PATH':'/snapshot/kg','TRACECAG_EXPECTED_KG_SHA256':'a'*64}},tmp_path/'run.log',run_id='day-01-id',suite_id='hotpotqa')
 assert captured['env']['TRACECAG_RUN_ID']=='day-01-id'
 assert captured['env']['TRACECAG_STAGE_ID']=='full'
 assert captured['env']['TRACECAG_SUITE_ID']=='hotpotqa'
 assert captured['env']['KUZU_DB_PATH']=='/snapshot/kg'
 assert captured['env']['TRACECAG_EXPECTED_KG_SHA256']=='a'*64

def test_run_stage_uses_writable_verified_isolated_kg_copy(tmp_path, monkeypatch):
 source=tmp_path/'frozen.db';source.write_bytes(b'frozen-kuzu-snapshot');source.chmod(0o444)
 expected=daily.snapshot_sha256(source)
 report=tmp_path/'report.json'
 captured={}
 class Result:returncode=0
 def fake_run(command, **kwargs):
  working=Path(kwargs['env']['KUZU_DB_PATH'])
  captured.update(path=working,mode=working.stat().st_mode & 0o777,pre_hash=daily.snapshot_sha256(working),env=kwargs['env'])
  assert working.resolve()!=source.resolve()
  assert os.access(working,os.W_OK)
  report.write_text(json.dumps({'run_validation':{'passed':True,'violations':[]}}))
  return Result()
 monkeypatch.setattr(daily.subprocess,'run',fake_run)
 stage={'name':'preflight','command':['benchmark'],'outputs':[report],'validator':'public',
        'environment':{},'kg_snapshot_source':source,'kg_snapshot_sha256':expected}
 assert daily.run_stage(stage,tmp_path/'run.log')==0
 value=json.loads(report.read_text())['kg_runtime_provenance']
 assert captured['pre_hash']==expected
 assert captured['mode'] & 0o200
 assert captured['env']['TRACECAG_KG_STRICT_SNAPSHOT']=='true'
 assert value['working_copy_pre_sha256']==expected
 assert value['working_copy_path_distinct'] is True
 assert value['working_copy_writable'] is True
 assert value['working_copy_isolated'] is True
 assert value['source_unchanged'] is True
 assert source.read_bytes()==b'frozen-kuzu-snapshot'
 assert source.stat().st_mode & 0o222==0

def test_manifest_frozen_kg_snapshot_is_hash_stable_and_not_production_db(monkeypatch):
 from tracecag_bench.kg.preflight import run_kg_preflight,snapshot_sha256
 m=daily.load_manifest(daily.DEFAULT_MANIFEST);defaults=m['defaults']
 snapshot=daily.MODEL_ROOT/defaults['kg_snapshot']
 assert snapshot.resolve()!= (daily.MODEL_ROOT.parent/'data'/'kuzu_db').resolve()
 assert snapshot_sha256(snapshot)==defaults['kg_sha256']
 monkeypatch.setenv('KUZU_DB_PATH',str(snapshot))
 first=run_kg_preflight();second=run_kg_preflight()
 assert first['path']==second['path']==str(snapshot.resolve())
 assert first['sha256']==second['sha256']==defaults['kg_sha256']

def test_build_plan_fails_before_run_when_frozen_kg_hash_mismatches(tmp_path):
 m=daily.load_manifest(daily.DEFAULT_MANIFEST);m=copy.deepcopy(m)
 m['defaults']['kg_sha256']='0'*64
 try:daily.build_plan(m['days'][0],m,tmp_path/'day-01')
 except ValueError as exc:assert 'KG snapshot hash mismatch' in str(exc)
 else:raise AssertionError('tampered KG snapshot provenance was accepted')

def test_publish_progress_writes_validated_summary(tmp_path):
 from tracecag_bench.reporting.progress import marker_line,terminal_marker
 log=tmp_path/'full.log'
 log.write_text(marker_line(terminal_marker(run_id='run',stage_id='full',suite_id='suite',sample_id='a',completed_count=1,target_count=1,elapsed_seconds=2,completed_at='2026-07-13T12:00:00Z'))+'\n')
 output=tmp_path/'progress.json'
 summary=daily.publish_progress(log,output)
 assert summary['observations'][0]['sample_id']=='a'
 assert json.loads(output.read_text())['schema_version']=='tracecag.progress-summary.v1'
