# zip 을 푼 자리에서 실행한다. %LOCALAPPDATA%\Programs\ClaudePet 에 복사하고, 사용자 PATH 에 넣고, 훅을 설치한다.
# 사용법: powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
# 브라우저로 받은 zip 은 Mark-of-the-Web 이 붙어 SmartScreen 이 exe 를 막을 수 있다. 복사한 파일에서 표식을 지운다.
$ErrorActionPreference = "Stop"
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA "Programs\ClaudePet"

foreach ($name in "ClaudePetWin.exe", "claude-pet.exe") {
    if (-not (Test-Path (Join-Path $src $name))) { Write-Error "$name 이 없습니다. zip 을 푼 디렉터리에서 실행하세요." }
}

Get-Process ClaudePetWin -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Recurse -Force (Join-Path $src "*") $dest
Get-ChildItem -Recurse $dest | Unblock-File -ErrorAction SilentlyContinue
Write-Host "복사했습니다: $dest"

if (-not (Test-Path (Join-Path $env:SystemRoot "System32\vcruntime140.dll"))) {
    Write-Warning "Visual C++ 재배포 패키지가 없습니다. https://aka.ms/vs/17/release/vc_redist.x64.exe 를 설치해야 실행됩니다."
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ";") -notcontains $dest) {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$dest", "User")
    Write-Host "사용자 PATH 에 추가했습니다. 새 터미널부터 claude-pet 명령을 쓸 수 있습니다."
}

& (Join-Path $dest "claude-pet.exe") install-hooks
Write-Host ""
Write-Host "다음 단계:"
Write-Host "  1. `"$dest\claude-pet.exe`" add guga        (codex-pets.net 의 펫 받기)"
Write-Host "  2. `"$dest\ClaudePetWin.exe`"                 (펫 실행. 트레이 아이콘에서 로그인 시 실행을 켤 수 있다)"
Write-Host "  SmartScreen 이 막으면 '추가 정보' → '실행' 을 누른다. 서명이 없어서 나오는 경고다."
