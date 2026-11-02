"""Run actual RGB/overlay, unchanged video pages and disabled fallback on one source snapshot."""
from pathlib import Path
import json,os,subprocess,sys
from record_g1r_inputs import snapshot

ROOT=Path(__file__).resolve().parents[1]
def main():
    before=snapshot();results=[]
    tools=Path('D:/FPGAdemo/tools/iverilog/app')
    os.environ.setdefault('RTL_SIM','icarus_direct')
    os.environ.setdefault('IVERILOG',str(tools/'bin/iverilog.exe'))
    os.environ.setdefault('VVP',str(tools/'bin/vvp.exe'))
    os.environ['PYTHONUTF8']='1'
    steps=[('g1r_integration.log','run_tests.py',['tb_g2_rgb','tb_g1r_overlay']),
           ('g1r_core.log','verify_g1_core.py',[]),
           ('g1r_disabled.log','verify_g1_disabled.py',[]),
           ('g1r_structure.log','check_project.py',[]),
           ('g1r_metadata.log','test_project_structure.py',[])]
    for log,script,args in steps:
        with (ROOT/'reports'/log).open('w',encoding='utf8') as output:
            result=subprocess.run([sys.executable,str(ROOT/'scripts'/script),*args],cwd=ROOT,
                                  stdout=output,stderr=subprocess.STDOUT)
        results.append(dict(script=script,args=args,log='reports/'+log,exit_code=result.returncode))
        if result.returncode:
            print((ROOT/'reports'/log).read_text(encoding='utf8'));raise RuntimeError(script+' failed')
        print('G1R integration step PASS:',script,flush=True)
    assert snapshot()==before,'RTL changed during integration checks'
    report=dict(status='PASS',board_tested=False,inputs=before,tests=results)
    (ROOT/'reports/g1r_integration_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print('G1R FINAL INTEGRATION PASS')
if __name__=='__main__':main()
