$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$efinityRoot='D:/efinity/2026.1'
$env:EFINITY_HOME=$efinityRoot
$env:EFXPT_HOME='D:/FPGAdemo/tools/efinity_pt'
$env:EFXPGM_HOME="$efinityRoot/pgm"
$env:EFXDBG_HOME="$efinityRoot/debugger"
$env:EFXIPM_HOME="$efinityRoot/ipm"
$env:PYTHONHOME="$efinityRoot/python311"
$env:PYTHONUTF8='1';$env:PYTHONUNBUFFERED='1'
$env:QT_PLUGIN_PATH="$efinityRoot/python311"
$env:PATH="$efinityRoot/python311/bin;$efinityRoot/bin;$efinityRoot/pgm/bin;$efinityRoot/scripts;"+$env:PATH
$buildWork=Join-Path $projectRoot 'work'
New-Item -ItemType Directory -Path $buildWork -Force | Out-Null
$env:EFINITY_USER_DIR_INI=Join-Path $buildWork 'efinity_user.ini'
Set-Content -LiteralPath $env:EFINITY_USER_DIR_INI -Value "[General]`nEFINITY_USER_DIR=$($buildWork.Replace('\','/'))/efinity_user" -Encoding ascii
Push-Location -LiteralPath $projectRoot
try {
    & "$efinityRoot/python311/bin/python.exe" scripts/record_g1r_inputs.py
    if($LASTEXITCODE -ne 0){throw "Cannot record G1R build inputs"}
    & "$efinityRoot/bin/efx_run.bat" ti60f225_oob.xml --flow compile
    if($LASTEXITCODE -ne 0){throw "Efinity G1R failed: $LASTEXITCODE"}
    & "$efinityRoot/python311/bin/python.exe" scripts/record_g1r_inputs.py --check
    if($LASTEXITCODE -ne 0){throw "G1R sources changed while compiling"}
} finally {Pop-Location}
