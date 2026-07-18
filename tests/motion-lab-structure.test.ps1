$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT TRUE FAILED: $Message" }
}

function Assert-False([bool]$Condition, [string]$Message) {
    if ($Condition) { throw "ASSERT FALSE FAILED: $Message" }
}

$iosRoot = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path $iosRoot "project.yml"
$appPath = Join-Path $iosRoot "MotionLab\MotionLabApp.swift"
$viewPath = Join-Path $iosRoot "MotionLab\MotionLabView.swift"
$handoffPath = Join-Path $iosRoot "MOTION-LAB-HANDOFF.md"
$workflowPath = Join-Path $iosRoot "ci\motion-lab-preview.yml"

$project = Get-Content -Raw -Encoding UTF8 -LiteralPath $projectPath
Assert-True ($project -match 'iOS:\s*"26\.0"') "deployment target remains iOS 26"
Assert-True ($project -match '(?ms)^  YushiMotionLab:\s*\r?\n.*?type:\s*application.*?platform:\s*iOS.*?sources:\s*\r?\n\s*- MotionLab') "independent YushiMotionLab target"
Assert-True (Test-Path -LiteralPath $appPath) "MotionLab app entry point exists"
Assert-True (Test-Path -LiteralPath $viewPath) "MotionLab view exists"
Assert-True (Test-Path -LiteralPath $handoffPath) "handoff is stored in private apps/ios"

$motionSource = (Get-Content -Raw -Encoding UTF8 -LiteralPath $appPath) + "`n" +
    (Get-Content -Raw -Encoding UTF8 -LiteralPath $viewPath)
Assert-False ($motionSource -match 'import\s+YushiKit') "Motion Lab must not import YushiKit"
Assert-False ($motionSource -match 'Gateway|ProviderEvent|tool_call') "Motion Lab must not reference business events"

Assert-True (Test-Path -LiteralPath $workflowPath) "Motion Lab preview workflow exists"
$workflow = Get-Content -Raw -Encoding UTF8 -LiteralPath $workflowPath
Assert-True ($workflow -match 'runs-on:\s*macos-26') "workflow uses macos-26"
Assert-True ($workflow -match '-scheme\s+YushiMotionLab') "workflow builds the Motion Lab scheme"
Assert-True ($workflow -match 'simctl\s+install') "workflow installs the simulator app"
Assert-True ($workflow -match 'simctl\s+launch') "workflow launches the simulator app"
Assert-True ($workflow -match 'recordVideo') "workflow records MP4"
Assert-True ($workflow -match 'Recording started') "workflow waits for simulator recording readiness"
Assert-True ($workflow -match 'wait\(timeout=') "workflow bounds recorder shutdown"
Assert-False ($workflow -match '(?ms)recordVideo.+?&\s*\r?\n\s*RECORDER_PID=.*?\r?\n\s*sleep\s+10') "workflow must not start the capture clock before recording is ready"
Assert-True ($workflow -match 'simctl\s+io.+screenshot') "workflow captures PNG"
Assert-True ($workflow -match 'actions/upload-artifact@v4') "workflow uploads preview artifacts"
Assert-True ($workflow -match 'name:\s*motion-lab-preview') "artifact has a stable name"

Write-Output "PASS: Motion Lab target is isolated"
