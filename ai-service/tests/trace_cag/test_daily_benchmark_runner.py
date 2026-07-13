import importlib.util,json,subprocess,sys
from pathlib import Path
P=Path(__file__).parents[2]/'model-development'/'benchmark'/'run_daily_benchmark.py';S=importlib.util.spec_from_file_location('daily_benchmark',P);daily=importlib.util.module_from_spec(S);S.loader.exec_module(daily)
sys.path.insert(0,str(P.parent))
def test_manifest_schedule():
 m=daily.load_manifest(daily.DEFAULT_MANIFEST);assert [x.get('n') for x in m['days'][:4]]==[64,64,32,500];assert m['defaults']['preflight_n']==5
def test_command_is_strict(tmp_path):
 m=daily.load_manifest(daily.DEFAULT_MANIFEST);c=daily.public_command(m['days'][0],m['defaults'],5,tmp_path/'r.json');assert c[c.index('--n')+1]=='5';assert '--no-allow-fallback' in c;assert '--no-allow-degraded-provider' in c
def test_report_requires_passed_true(tmp_path):
 p=tmp_path/'r.json';p.write_text(json.dumps({'run_validation':{'passed':True}}));stage={'validator':'public','outputs':[p]};assert daily.valid_output(stage);p.write_text('{}');assert not daily.valid_output(stage)

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
 daily.run_stage({'name':'full','command':['benchmark'],'outputs':[],'validator':'exit'},tmp_path/'run.log',run_id='day-01-id',suite_id='hotpotqa')
 assert captured['env']['TRACECAG_RUN_ID']=='day-01-id'
 assert captured['env']['TRACECAG_STAGE_ID']=='full'
 assert captured['env']['TRACECAG_SUITE_ID']=='hotpotqa'

def test_publish_progress_writes_validated_summary(tmp_path):
 from tracecag_bench.reporting.progress import marker_line,terminal_marker
 log=tmp_path/'full.log'
 log.write_text(marker_line(terminal_marker(run_id='run',stage_id='full',suite_id='suite',sample_id='a',completed_count=1,target_count=1,elapsed_seconds=2,completed_at='2026-07-13T12:00:00Z'))+'\n')
 output=tmp_path/'progress.json'
 summary=daily.publish_progress(log,output)
 assert summary['observations'][0]['sample_id']=='a'
 assert json.loads(output.read_text())['schema_version']=='tracecag.progress-summary.v1'
