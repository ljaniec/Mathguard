#!/usr/bin/env python3
"""Run real-worker integration tests and record exact, fixture-labeled evidence."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))

class RecordedResult(unittest.TextTestResult):
    records=[]
    def startTest(self,test):
        self.started=time.monotonic()
        super().startTest(test)
    def record(self,test,status):
        self.records.append({'test':test.id(),'status':status,'seconds':time.monotonic()-self.started})
    def addSuccess(self,test):super().addSuccess(test);self.record(test,'passed')
    def addFailure(self,test,err):super().addFailure(test,err);self.record(test,'failed')
    def addError(self,test,err):super().addError(test,err);self.record(test,'error')
    def addSkip(self,test,reason):super().addSkip(test,reason);self.record(test,'skipped')


def main():
    paths=[*(ROOT/'Mathguard').rglob('*.lean'),ROOT/'Main.lean',ROOT/'scripts/Axioms.lean',
           ROOT/'lakefile.toml',ROOT/'lean-toolchain',ROOT/'lake-manifest.json']
    for folder in ['gateway','agent','dashboard','policies','feeds','contracts','tests','scripts']:
        paths.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in {'.py','.sh','.json','.jsonl','.js','.css','.html','.lean'})
    source={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}
    suite=unittest.defaultTestLoader.discover(str(ROOT/'tests'),pattern='test_*.py')
    result=unittest.TextTestRunner(verbosity=2,resultclass=RecordedResult).run(suite)
    report={'collected_at_utc':datetime.now(timezone.utc).isoformat(),'python':platform.python_version(),
      'platform':platform.platform(),'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
      'source_sha256':source,'worker_sha256':hashlib.sha256((ROOT/'.lake/build/bin/mathguard-worker').read_bytes()).hexdigest(),
      'tests_run':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),
      'passed':result.wasSuccessful(),'tests':result.records,
      'semantic_evidence':'FixtureProvider for enforcement; local HTTP protocol fixture for transport; no real LLM inference measured',
      'kernel_evidence':'Actual compiled Lean worker, not a Python ledger mirror',
      'ui_evidence':'Dashboard markup and JavaScript DOM/request behavior tested; browser visual/download QA remains pending',
      'claim':'Runtime regressions, not a whole-stack theorem or classifier accuracy benchmark'}
    output=ROOT/'evidence/integration.json';output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report,indent=2)+'\n')
    print('Evidence: evidence/integration.json')
    raise SystemExit(0 if result.wasSuccessful() else 1)

if __name__=='__main__':main()
