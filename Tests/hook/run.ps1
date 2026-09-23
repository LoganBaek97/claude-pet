# Windows 네이티브 훅 통합 테스트. 사용법: pwsh Tests/hook/run.ps1  (또는 powershell -File)
# 1) claude-pet.exe hook 에 픽스처를 직접 넣어 상태 파일을 확인한다 (run.sh 의 단언을 미러링).
# 2) install-hooks 가 만든 명령 문자열을 실제 셸(bash, powershell.exe, pwsh)로 돌려 상태 파일이 나오는지 본다.
#    Claude Code 는 sh -c 로, Codex 는 commandWindows 를 PowerShell 문장으로 돌리므로 이 층이 진짜 계약이다.
# 3) 콜드 스타트를 재서 SessionEnd 예산(Claude 1.5초 공유, Codex 1초) 안에 드는지 본다.
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$OutputEncoding = [Text.UTF8Encoding]::new()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-Path (Join-Path $here "..\..")
$fix = Join-Path $here "fixtures"
$bin = (& swift build --show-bin-path).Trim()
$exe = Join-Path $bin "claude-pet.exe"
if (-not (Test-Path $exe)) { throw "claude-pet.exe 가 없습니다: $exe (swift build 먼저)" }

$script:fail = 0
function Assert-Eq($name, $expected, $actual) {
    if ("$expected" -eq "$actual") { Write-Host "ok   $name" }
    else { Write-Host "FAIL $name"; Write-Host "  expected: $expected"; Write-Host "  actual:   $actual"; $script:fail = 1 }
}
function New-StateDir { $d = Join-Path ([IO.Path]::GetTempPath()) ("claude-pet-hook-" + [Guid]::NewGuid()); New-Item -ItemType Directory -Path $d | Out-Null; $d }
function Read-State($dir, $id) { Get-Content -Raw -Encoding UTF8 (Join-Path $dir "$id.json") | ConvertFrom-Json }
function Fixture-Id($name) { (Get-Content -Raw -Encoding UTF8 (Join-Path $fix $name) | ConvertFrom-Json).session_id }
# stdin 을 파이프로 주는 방식은 Claude Code 가 훅을 띄우는 방식과 같다. cmd 의 리다이렉션을 써서
# PowerShell 의 파이프 인코딩 층을 끼우지 않는다.
function Invoke-WithStdin([string]$commandLine, [string]$fixture) {
    & cmd /c "$commandLine < `"$fixture`"" | Out-Null
    return $LASTEXITCODE
}

Remove-Item Env:CLAUDE_CODE_HOST_SESSION_ID -ErrorAction SilentlyContinue

# ---------- 1. 직접 실행 ----------
$state = New-StateDir
$env:CLAUDE_PET_STATE_DIR = $state

Assert-Eq "exit0 pre-tool-use" 0 (Invoke-WithStdin "`"$exe`" hook" (Join-Path $fix "pre-tool-use.json"))
$s = Read-State $state "sess-1"
Assert-Eq "state running" "running" $s.state
Assert-Eq "event" "PreToolUse" $s.event
Assert-Eq "tool" "Bash" $s.tool
Assert-Eq "cwd" "/Users/x/proj" $s.cwd
Assert-Eq "transcript" "/Users/x/.claude/projects/p/sess-1.jsonl" $s.transcript
Assert-Eq "agent claude" "claude" $s.agent
Assert-Eq "host_session empty" "" $s.host_session
Assert-Eq "agent_pid is number" $true ($s.agent_pid -is [long] -or $s.agent_pid -is [int])

Assert-Eq "exit0 permission-request" 0 (Invoke-WithStdin "`"$exe`" hook" (Join-Path $fix "permission-request.json"))
Assert-Eq "state waiting" "waiting" (Read-State $state (Fixture-Id "permission-request.json")).state

Assert-Eq "exit0 hangul" 0 (Invoke-WithStdin "`"$exe`" hook" (Join-Path $fix "pre-tool-use-hangul.json"))
$h = Get-Content -Raw -Encoding UTF8 (Join-Path $fix "pre-tool-use-hangul.json") | ConvertFrom-Json
$hs = Read-State $state $h.session_id
Assert-Eq "hangul cwd intact" $h.cwd $hs.cwd
Assert-Eq "hangul tool intact" $h.tool_name $hs.tool

Assert-Eq "exit0 codex interrupt" 0 (Invoke-WithStdin "`"$exe`" hook --agent codex" (Join-Path $fix "codex-interrupt.json"))
$c = Read-State $state "codex-1"
Assert-Eq "codex agent" "codex" $c.agent
Assert-Eq "interrupt idle" "idle" $c.state

$env:CLAUDE_CODE_HOST_SESSION_ID = "local_abc-123"
Assert-Eq "exit0 host session" 0 (Invoke-WithStdin "`"$exe`" hook" (Join-Path $fix "stop.json"))
Assert-Eq "host_session kept" "local_abc-123" (Read-State $state (Fixture-Id "stop.json")).host_session
Remove-Item Env:CLAUDE_CODE_HOST_SESSION_ID

Assert-Eq "exit0 session-end" 0 (Invoke-WithStdin "`"$exe`" hook" (Join-Path $fix "session-end.json"))
Assert-Eq "session-end removes" $false (Test-Path (Join-Path $state "$(Fixture-Id 'session-end.json').json"))

Assert-Eq "exit0 no-session" 0 (Invoke-WithStdin "`"$exe`" hook" (Join-Path $fix "no-session.json"))
Assert-Eq "exit0 unknown-event" 0 (Invoke-WithStdin "`"$exe`" hook" (Join-Path $fix "unknown-event.json"))
# 남는 파일: session-end 가 지운 것을 뺀 나머지 세션들.
$expectedIds = @("pre-tool-use.json", "permission-request.json", "pre-tool-use-hangul.json", "codex-interrupt.json", "stop.json") |
    ForEach-Object { Fixture-Id $_ } | Where-Object { $_ -ne (Fixture-Id "session-end.json") } | Sort-Object -Unique
Assert-Eq "no stray files" $expectedIds.Count ((Get-ChildItem $state -Filter *.json).Count)

# ---------- 2. 설치기가 만든 명령을 실제 셸로 ----------
$home2 = New-StateDir
$env:USERPROFILE = $home2
$env:HOME = $home2
New-Item -ItemType Directory -Force -Path (Join-Path $home2 ".codex") | Out-Null
# corelibs 가 USERPROFILE 대신 셸 API 로 홈을 잡으면 진짜 프로필에 설치된다. 둘 다 본다.
$realHome = [Environment]::GetFolderPath("UserProfile")
New-Item -ItemType Directory -Force -Path (Join-Path $realHome ".codex") | Out-Null
& $exe install-hooks
Assert-Eq "install-hooks exit0" 0 $LASTEXITCODE
$settingsPath = @((Join-Path $home2 ".claude\settings.json"), (Join-Path $realHome ".claude\settings.json")) | Where-Object { Test-Path $_ } | Select-Object -First 1
$codexPath = @((Join-Path $home2 ".codex\hooks.json"), (Join-Path $realHome ".codex\hooks.json")) | Where-Object { Test-Path $_ } | Select-Object -First 1
Assert-Eq "settings.json written" $true ($null -ne $settingsPath)
Assert-Eq "hooks.json written" $true ($null -ne $codexPath)

function Our-Entry($file, $event) {
    $j = Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json
    foreach ($g in $j.hooks.$event) { foreach ($h in $g.hooks) {
        if (("$($h.command)").EndsWith("# claude-pet") -or ("$($h.commandWindows)").EndsWith("# claude-pet")) { return $h }
    } }
    return $null
}

$state2 = New-StateDir
$env:CLAUDE_PET_STATE_DIR = $state2
$claude = Our-Entry $settingsPath "PreToolUse"
Assert-Eq "claude entry exists" $true ($null -ne $claude)
if ($claude) {
    Write-Host "  claude command: $($claude.command)"
    Write-Host "  claude shell:   $($claude.shell)"
    $tmp = Join-Path $state2 "claude-cmd"
    if ($claude.shell -eq "powershell") {
        Set-Content -Path "$tmp.ps1" -Value $claude.command -Encoding UTF8
        Assert-Eq "claude powershell form exit0" 0 (Invoke-WithStdin "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$tmp.ps1`"" (Join-Path $fix "pre-tool-use-hangul.json"))
    } else {
        Set-Content -Path "$tmp.sh" -Value $claude.command -Encoding UTF8
        Assert-Eq "claude bash form exit0" 0 (Invoke-WithStdin "bash `"$tmp.sh`"" (Join-Path $fix "pre-tool-use-hangul.json"))
    }
    $r = Read-State $state2 $h.session_id
    Assert-Eq "claude form wrote state" "running" $r.state
    Assert-Eq "claude form cwd intact" $h.cwd $r.cwd
    Remove-Item (Join-Path $state2 "$($h.session_id).json")
}

$codex = Our-Entry $codexPath "PreToolUse"
Assert-Eq "codex entry exists" $true ($null -ne $codex)
if ($codex) {
    Write-Host "  codex commandWindows: $($codex.commandWindows)"
    Assert-Eq "codex has commandWindows" $true (-not [string]::IsNullOrEmpty($codex.commandWindows))
    $tmp = Join-Path $state2 "codex-cmd.ps1"
    Set-Content -Path $tmp -Value $codex.commandWindows -Encoding UTF8
    foreach ($shell in "powershell.exe", "pwsh") {
        if (-not (Get-Command $shell -ErrorAction SilentlyContinue)) { Write-Host "skip $shell (없음)"; continue }
        Assert-Eq "codex form via $shell exit0" 0 (Invoke-WithStdin "$shell -NoProfile -ExecutionPolicy Bypass -File `"$tmp`"" (Join-Path $fix "pre-tool-use-hangul.json"))
        $r = Read-State $state2 $h.session_id
        Assert-Eq "codex form via $shell agent" "codex" $r.agent
        Assert-Eq "codex form via $shell cwd intact" $h.cwd $r.cwd
        Remove-Item (Join-Path $state2 "$($h.session_id).json")
    }
}

# ---------- 3. 콜드 스타트 ----------
$env:CLAUDE_PET_STATE_DIR = $state
$times = @()
for ($i = 0; $i -lt 10; $i++) {
    $t = Measure-Command { Invoke-WithStdin "`"$exe`" hook" (Join-Path $fix "pre-tool-use.json") | Out-Null }
    $times += $t.TotalMilliseconds
}
$sorted = $times | Sort-Object
$median = $sorted[[int]($sorted.Count / 2)]
Write-Host ("cold start ms: median {0:N0}  min {1:N0}  max {2:N0}" -f $median, $sorted[0], $sorted[-1])
if ($median -gt 800) { Write-Host "FAIL cold start median > 800ms"; $script:fail = 1 }
elseif ($median -gt 300) { Write-Warning "cold start median > 300ms (게이트 목표)" }

if ($script:fail -eq 0) { Write-Host "ALL OK" } else { exit 1 }
