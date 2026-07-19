param(
    [string]$BuildDir = "_site",
    [string]$PagesDir = "_pages"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    & git @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode."
    }

    return $exitCode
}

if (-not (Test-Path -LiteralPath $BuildDir -PathType Container)) {
    throw "Build directory '$BuildDir' does not exist."
}

Invoke-Git -Arguments @("config", "user.name", "github-actions[bot]")
Invoke-Git -Arguments @("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")

Invoke-Git -Arguments @("fetch", "origin", "gh-pages") -AllowFailure | Out-Null
$hasGhPages = (Invoke-Git -Arguments @("show-ref", "--verify", "--quiet", "refs/remotes/origin/gh-pages") -AllowFailure) -eq 0

if ($hasGhPages) {
    Invoke-Git -Arguments @("worktree", "add", $PagesDir, "origin/gh-pages")
} else {
    Invoke-Git -Arguments @("worktree", "add", "-B", "gh-pages", $PagesDir, "HEAD")
}

Get-ChildItem -LiteralPath $PagesDir -Force |
    Where-Object { $_.Name -notin @(".git", "previews") } |
    Remove-Item -Recurse -Force

Get-ChildItem -LiteralPath $BuildDir -Force |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $PagesDir -Recurse -Force
    }

New-Item -Path (Join-Path $PagesDir ".nojekyll") -ItemType File -Force | Out-Null

$status = (& git -C $PagesDir status --porcelain)
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host "No live site changes to publish."
    exit 0
}

Invoke-Git -Arguments @("-C", $PagesDir, "add", "-A")
Invoke-Git -Arguments @("-C", $PagesDir, "commit", "-m", "Deploy live site from main")
Invoke-Git -Arguments @("-C", $PagesDir, "push", "origin", "HEAD:gh-pages")
