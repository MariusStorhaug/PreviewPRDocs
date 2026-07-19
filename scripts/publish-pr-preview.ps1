param(
    [string]$BuildDir = "_site",
    [Parameter(Mandatory = $true)]
    [string]$PrNumber,
    [Parameter(Mandatory = $true)]
    [string]$PrAction,
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

Invoke-Git -Arguments @("config", "user.name", "github-actions[bot]")
Invoke-Git -Arguments @("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")

Invoke-Git -Arguments @("fetch", "origin", "gh-pages") -AllowFailure | Out-Null
$hasGhPages = (Invoke-Git -Arguments @("show-ref", "--verify", "--quiet", "refs/remotes/origin/gh-pages") -AllowFailure) -eq 0
$bootstrappedBranch = $false

if (-not $hasGhPages) {
    if ($PrAction -eq "closed") {
        Write-Host "gh-pages does not exist; nothing to clean."
        exit 0
    }

    $bootstrappedBranch = $true
    Invoke-Git -Arguments @("worktree", "add", "-B", "gh-pages", $PagesDir, "HEAD")
} else {
    Invoke-Git -Arguments @("worktree", "add", $PagesDir, "origin/gh-pages")
}

if ($bootstrappedBranch) {
    Get-ChildItem -LiteralPath $PagesDir -Force |
        Where-Object { $_.Name -notin @(".git", "previews") } |
        Remove-Item -Recurse -Force
}

if ($PrAction -ne "closed" -and -not (Test-Path -LiteralPath $BuildDir -PathType Container)) {
    throw "Build directory '$BuildDir' does not exist."
}

$previewDir = Join-Path $PagesDir "previews/pr-$PrNumber"

for ($attempt = 1; $attempt -le 3; $attempt++) {
    if ($attempt -gt 1) {
        Invoke-Git -Arguments @("fetch", "origin", "gh-pages") -AllowFailure | Out-Null
        $hasRemoteGhPages = (Invoke-Git -Arguments @("show-ref", "--verify", "--quiet", "refs/remotes/origin/gh-pages") -AllowFailure) -eq 0
        if ($hasRemoteGhPages) {
            Invoke-Git -Arguments @("-C", $PagesDir, "fetch", "origin", "gh-pages")
            Invoke-Git -Arguments @("-C", $PagesDir, "reset", "--hard", "origin/gh-pages")
        }
    }

    New-Item -Path (Join-Path $PagesDir ".nojekyll") -ItemType File -Force | Out-Null

    if ($PrAction -eq "closed") {
        if (Test-Path -LiteralPath $previewDir) {
            Remove-Item -LiteralPath $previewDir -Recurse -Force
        }
        $commitMessage = "Remove preview for PR #$PrNumber"
    } else {
        if (Test-Path -LiteralPath $previewDir) {
            Remove-Item -LiteralPath $previewDir -Recurse -Force
        }

        New-Item -Path $previewDir -ItemType Directory -Force | Out-Null
        Get-ChildItem -LiteralPath $BuildDir -Force |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $previewDir -Recurse -Force
            }
        $commitMessage = "Update preview for PR #$PrNumber"
    }

    $status = (& git -C $PagesDir status --porcelain)
    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Host "No preview changes to publish."
        exit 0
    }

    Invoke-Git -Arguments @("-C", $PagesDir, "add", "-A")
    Invoke-Git -Arguments @("-C", $PagesDir, "commit", "-m", $commitMessage)

    $pushExitCode = Invoke-Git -Arguments @("-C", $PagesDir, "push", "origin", "HEAD:gh-pages") -AllowFailure
    if ($pushExitCode -eq 0) {
        exit 0
    }

    if ($attempt -eq 3) {
        throw "Failed to push preview update after 3 attempts."
    }

    Write-Host "Push failed due to concurrent update, retrying..."
}
