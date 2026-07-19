param(
    [Parameter(Mandatory = $true)]
    [string]$PrNumber,
    [Parameter(Mandatory = $true)]
    [string]$PrAction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    throw "GITHUB_TOKEN must be available in the environment."
}

if ([string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
    throw "GITHUB_REPOSITORY must be available in the environment."
}

$repoParts = $env:GITHUB_REPOSITORY -split "/", 2
if ($repoParts.Length -ne 2) {
    throw "Invalid GITHUB_REPOSITORY value '$($env:GITHUB_REPOSITORY)'."
}

$owner = $repoParts[0]
$repo = $repoParts[1]
$environmentName = "pr-preview-$PrNumber"
$previewUrl = "https://$($owner.ToLowerInvariant()).github.io/$repo/previews/pr-$PrNumber/"
$runUrl = "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
$environmentDeleteToken = if ([string]::IsNullOrWhiteSpace($env:PREVIEW_ENV_ADMIN_TOKEN)) {
    $env:GITHUB_TOKEN
} else {
    $env:PREVIEW_ENV_ADMIN_TOKEN
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST", "DELETE")]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [object]$Body,
        [string]$Token = $env:GITHUB_TOKEN
    )

    $headers = @{
        Authorization = "Bearer $Token"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    $invokeParams = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
        ErrorAction = "Stop"
    }

    if ($null -ne $Body) {
        $invokeParams.ContentType = "application/json"
        $invokeParams.Body = ($Body | ConvertTo-Json -Depth 10)
    }

    return Invoke-RestMethod @invokeParams
}

function Get-HttpStatusCode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($null -eq $ErrorRecord.Exception.Response) {
        return $null
    }

    return [int]$ErrorRecord.Exception.Response.StatusCode
}

$baseUrl = "https://api.github.com/repos/$owner/$repo"

if ($PrAction -eq "closed") {
    $deployments = Invoke-GitHubApi -Method "GET" -Uri "$baseUrl/deployments?environment=$environmentName&per_page=100"
    foreach ($deployment in @($deployments)) {
        Invoke-GitHubApi -Method "POST" -Uri "$baseUrl/deployments/$($deployment.id)/statuses" -Body @{
            state = "inactive"
            description = "Preview removed after PR close"
            log_url = $runUrl
        } | Out-Null
    }

    $encodedEnvironmentName = [System.Uri]::EscapeDataString($environmentName)
    try {
        Invoke-GitHubApi -Method "DELETE" -Uri "$baseUrl/environments/$encodedEnvironmentName" -Token $environmentDeleteToken | Out-Null
        Write-Host "Deleted environment '$environmentName'."
    } catch {
        $statusCode = Get-HttpStatusCode -ErrorRecord $_
        if ($statusCode -eq 404) {
            Write-Host "Environment '$environmentName' does not exist."
        } elseif ($statusCode -eq 403 -and [string]::IsNullOrWhiteSpace($env:PREVIEW_ENV_ADMIN_TOKEN)) {
            throw "Failed to delete environment '$environmentName' with GITHUB_TOKEN. Configure GitHub App secrets PREVIEW_APP_ID and PREVIEW_APP_PRIVATE_KEY, or set PREVIEW_ENV_ADMIN_TOKEN with a token that can administer repository environments."
        } else {
            throw "Failed to delete environment '$environmentName': $($_.Exception.Message)"
        }
    }

    exit 0
}

$deployment = Invoke-GitHubApi -Method "POST" -Uri "$baseUrl/deployments" -Body @{
    ref = $env:GITHUB_SHA
    task = "deploy"
    auto_merge = $false
    required_contexts = @()
    environment = $environmentName
    description = "PR preview for #$PrNumber"
    transient_environment = $true
    production_environment = $false
}

Invoke-GitHubApi -Method "POST" -Uri "$baseUrl/deployments/$($deployment.id)/statuses" -Body @{
    state = "success"
    description = "Preview available"
    environment_url = $previewUrl
    log_url = $runUrl
} | Out-Null

Write-Host "Updated environment '$environmentName' with URL: $previewUrl"
