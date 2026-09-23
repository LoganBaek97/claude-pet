# swift build 결과를 dist\ClaudePet-windows-x64\ 로 모으고 zip 으로 싼다.
# 사용법: powershell -ExecutionPolicy Bypass -File scripts\bundle-windows.ps1 [-Configuration release|debug] [-NoZip]
# GUI 실행 파일은 콘솔 창이 뜨지 않게 /SUBSYSTEM:WINDOWS 로 링크한다. Swift 는 main 을 만들고 WinMain 은
# 없으므로 /ENTRY:mainCRTStartup 을 함께 준다. CLI(claude-pet.exe)는 콘솔 앱으로 남긴다.
param(
    [ValidateSet("release", "debug")] [string] $Configuration = "release",
    [switch] $NoZip
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
    Write-Error "swift 가 없습니다. https://www.swift.org/install/windows/ 를 참고해 설치하세요."
}

Write-Host "== swift build ($Configuration)"
swift build -c $Configuration --product claude-pet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
swift build -c $Configuration --product ClaudePetWin -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$bin = (swift build -c $Configuration --show-bin-path).Trim()

$out = Join-Path $root "dist\ClaudePet-windows-x64"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path (Join-Path $out "pets") | Out-Null

Copy-Item (Join-Path $bin "ClaudePetWin.exe") $out
Copy-Item (Join-Path $bin "claude-pet.exe") $out
Copy-Item -Recurse (Join-Path $root "Resources\pets\default") (Join-Path $out "pets\default")
Copy-Item (Join-Path $root "scripts\install-windows.ps1") $out
if (Test-Path (Join-Path $root "README-windows.md")) { Copy-Item (Join-Path $root "README-windows.md") $out }

# Swift 런타임 DLL. 툴체인은 %SDKROOT% = <Swift>\Platforms\Windows.platform\Developer\SDKs\Windows.sdk 를
# 내보내고 런타임은 <Swift>\Runtimes\<버전>\usr\bin 에 있다. 정적 링크가 가능해지면 이 단계는 없어진다.
$runtime = $null
if ($env:SDKROOT) {
    $swiftRoot = Resolve-Path (Join-Path $env:SDKROOT "..\..\..\..\..")
    $candidates = Get-ChildItem -Directory (Join-Path $swiftRoot "Runtimes") -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($c in $candidates) {
        $p = Join-Path $c.FullName "usr\bin"
        if (Test-Path (Join-Path $p "swiftCore.dll")) { $runtime = $p; break }
    }
}
if (-not $runtime) {
    $found = Get-ChildItem -Recurse -Filter swiftCore.dll -Path "C:\Program Files\Swift" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { $runtime = $found.DirectoryName }
}
if ($runtime) {
    Write-Host "== 런타임 DLL: $runtime"
    Copy-Item (Join-Path $runtime "*.dll") $out
} else {
    Write-Warning "Swift 런타임 DLL 디렉터리를 찾지 못했습니다. zip 을 받은 기계에 Swift 런타임이 없으면 실행되지 않습니다."
}

# 어떤 DLL 에 의존하는지 기록해 둔다(릴리스 로그 확인용).
$dumpbin = Get-Command dumpbin -ErrorAction SilentlyContinue
if ($dumpbin) {
    & $dumpbin /dependents (Join-Path $out "ClaudePetWin.exe") | Select-String "\.dll" | ForEach-Object { $_.Line.Trim() } |
        Set-Content (Join-Path $out "DEPENDENTS.txt")
}

Write-Host "== 산출물"
Get-ChildItem -Recurse $out | Where-Object { -not $_.PSIsContainer } |
    ForEach-Object { "{0,10:N0}  {1}" -f $_.Length, $_.FullName.Substring($out.Length + 1) }

if (-not $NoZip) {
    $zip = Join-Path $root "dist\ClaudePet-windows-x64.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip
    Write-Host "built $zip"
}
