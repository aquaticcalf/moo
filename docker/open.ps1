param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Command
)

$ErrorActionPreference = "Stop"

$mooCacheDirectory = Join-Path $env:USERPROFILE ".moo"
if (-not (Test-Path -LiteralPath $mooCacheDirectory)) {
    New-Item -ItemType Directory -Path $mooCacheDirectory -Force | Out-Null
}
$env:MOO_CACHE_DIR = $mooCacheDirectory

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker was not found in PATH. install and start Docker Desktop first."
    exit 1
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $PSScriptRoot "compose.yaml"
$composeArguments = @(
    "compose",
    "--file",
    $composeFile,
    "run",
    "--rm",
    "--service-ports",
    "moo"
)

if ($Command.Count -eq 0) {
    $composeArguments += "bash"
} else {
    $composeArguments += $Command
}

Push-Location $repositoryRoot
try {
    & docker @composeArguments
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

exit $exitCode
