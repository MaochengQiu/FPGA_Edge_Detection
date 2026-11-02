"""Run official Icarus ivlpp/ivl stages directly, without its crashing Windows driver.

Configuration matches driver/main.c (v12-branch). Each subprocess must exit 0;
compiler/simulator errors are never ignored. No shell pipeline is involved.
"""
from pathlib import Path
import os
import subprocess


def compile_sources(sources, top, output, cwd, params=None, includes=()):
    base=Path(os.environ.get('IVL_BASE',r'D:\FPGAdemo\tools\iverilog\app\lib\ivl'))
    cwd=Path(cwd);output=Path(output)
    prefix=cwd/(output.stem+'_direct')
    files=prefix.with_suffix('.files');flags=prefix.with_suffix('.flags')
    config=prefix.with_suffix('.conf');preprocessed=prefix.with_suffix('.pp.v')
    files.write_text(''.join(str(Path(p))+'\n' for p in sources),encoding='utf-8')
    flags.write_text('D:__ICARUS__=1\n'+''.join(f'I:{p}\n' for p in includes)+
                     f'I:{base}/include\nrelative include:false\n',encoding='utf-8')
    settings=[f'root:{top}',f'basedir:{base}']
    settings += [f'module:{base}/{name}.vpi' for name in
                 ('system','vhdl_sys','vhdl_textio','v2005_math','va_math','v2009')]
    settings += [f'generation:{name}' for name in
                 ('2012','no-specify','assertions','xtypes','io-range-error','no-strict-ca-eval',
                  'no-strict-expr-width','shared-loop-index','no-verilog-ams','icarus-misc')]
    settings += ['warnings:anpr', 'ignore_missing_modules:false', f'out:{output}', 'iwidth:32','widthcap:65536']
    settings += [f'defparam:{top}.{key}={value}' for key,value in (params or {}).items()]
    config.write_text('\n'.join(settings)+'\n',encoding='utf-8')
    commands=[[str(base/'ivlpp.exe'),'-L','-F',str(flags),'-f',str(files)],
              [str(base/'ivl.exe'),'-C',str(config),'-C',str(base/'vvp.conf'),'--',str(preprocessed)]]
    with preprocessed.open('wb') as stream:
        first=subprocess.run(commands[0],cwd=cwd,stdout=stream,stderr=subprocess.PIPE)
    if first.returncode:
        return subprocess.CompletedProcess(commands[0],first.returncode,'',first.stderr.decode(errors='replace'))
    return subprocess.run(commands[1],cwd=cwd,text=True,capture_output=True)
