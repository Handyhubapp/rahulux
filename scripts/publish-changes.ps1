[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Message = 'Update website'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')"
    }

    return $output
}

function Test-WebsitePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path -eq 'AGENTS.md' -or $Path -eq 'scripts/publish-changes.ps1') {
        return $false
    }

    $isWebsitePath = $Path -eq 'index.html' -or
        $Path -eq 'favicon.ico' -or
        $Path.StartsWith('css/', [System.StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith('images/', [System.StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith('scripts/', [System.StringComparison]::OrdinalIgnoreCase)

    if (-not $isWebsitePath) {
        return $false
    }

    $isGenerated = $Path -match '(^|/)\.[^/]+$' -or
        $Path -match '(^|/)[^/]+\.min\.(css|js)$' -or
        $Path -match '\.map$'
    $looksSensitive = $Path -match '(?i)(^|/)(\.env|.*(secret|credential|token|password).*)$' -or
        $Path -match '(?i)\.(pem|key|pfx|p12)$'

    return -not ($isGenerated -or $looksSensitive)
}

function Test-LocalReferences {
    $htmlPath = Join-Path $repositoryRoot 'index.html'
    if (-not (Test-Path -LiteralPath $htmlPath -PathType Leaf)) {
        throw 'Validation failed: index.html was not found.'
    }

    $html = Get-Content -LiteralPath $htmlPath -Raw
    $matches = [regex]::Matches($html, '(?i)(?:href|src)\s*=\s*["'']([^"'']+)["'']')

    foreach ($match in $matches) {
        $reference = $match.Groups[1].Value
        if ($reference -match '^(#|//|[a-z][a-z0-9+.-]*:)') {
            continue
        }

        $relativeReference = ($reference -split '[?#]')[0]
        if ([string]::IsNullOrWhiteSpace($relativeReference)) {
            continue
        }

        $relativePath = [Uri]::UnescapeDataString($relativeReference).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $resolvedPath = Join-Path $repositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "Validation failed: index.html references missing local file '$reference'."
        }
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repositoryRoot

$currentBranch = (Invoke-Git @('branch', '--show-current')).Trim()
if ($currentBranch -ne 'main') {
    throw "Publishing stopped: current branch is '$currentBranch'; only main is allowed."
}

$originUrl = (Invoke-Git @('remote', 'get-url', 'origin')).Trim()
if ($originUrl -ne 'https://github.com/Handyhubapp/rahulux.git') {
    throw "Publishing stopped: origin is '$originUrl', not the existing expected GitHub remote."
}

$websiteRoots = @('index.html', 'favicon.ico', 'css', 'images', 'scripts')
$changedPaths = @()
$changedPaths += Invoke-Git (@('diff', '--name-only', 'HEAD', '--') + $websiteRoots)
$changedPaths += Invoke-Git (@('ls-files', '--others', '--exclude-standard', '--') + $websiteRoots)
$candidatePaths = @($changedPaths |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and (Test-WebsitePath -Path $_) } |
    Sort-Object -Unique)

if ($candidatePaths.Count -eq 0) {
    throw 'Publishing stopped: no intended, publishable website changes were found.'
}

Test-LocalReferences
Invoke-Git (@('diff', '--check', 'HEAD', '--') + $candidatePaths) | Out-Null

Invoke-Git (@('add', '--') + $candidatePaths) | Out-Null
Invoke-Git (@('diff', '--cached', '--check', '--') + $candidatePaths) | Out-Null
Invoke-Git (@('commit', '--only', '-m', $Message, '--') + $candidatePaths) | Out-Null
Invoke-Git @('push', 'origin', 'main:main') | Out-Null

Write-Output "Published website commit to origin/main: $Message"