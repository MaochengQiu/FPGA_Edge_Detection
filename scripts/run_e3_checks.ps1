param([ValidateSet('regression','local','images','structure')][string]$Suite='regression')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$env:PYTHONUTF8='1'
$env:PYTHONUNBUFFERED='1'
$env:PATH='D:\FPGAdemo\tools\iverilog\app\bin;'+$env:PATH
$env:TEMP='D:\FPGAdemo\tools\tmp'
$env:TMP=$env:TEMP
$env:IVERILOG='D:\FPGAdemo\tools\iverilog\app\bin\iverilog.exe'
$env:VVP='D:\FPGAdemo\tools\iverilog\app\bin\vvp.exe'
$env:RTL_SIM='icarus_direct'
$pythonExe='C:\Users\lenovo\AppData\Local\Programs\Python\Python313\python.exe'
$scripts=switch($Suite){
    'regression' {@('run_tests.py')}
    'local' {@('verify_e3.py')}
    'images' {@('verify_e3_images.py')}
    'structure' {@('check_project.py','test_project_structure.py')}
}
foreach($script in $scripts){
    & $pythonExe -u (Join-Path $PSScriptRoot $script)
    if($LASTEXITCODE -ne 0){throw "$script failed with exit code $LASTEXITCODE"}
}
