[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Shard,

    [ValidateRange(0, 1000000)]
    [int] $RecordLimit = 20,

    [ValidateRange(0, 1000000)]
    [int] $TermLimit = 1000,

    [ValidateRange(0, 1000000)]
    [int] $PostingLimit = 10000,

    [string] $OutputPath,

    [string] $InspectorRoot,

    [switch] $IndexesOnly,

    [switch] $Html,

    [switch] $NoHtml,

    [string] $HtmlOutputPath,

    [switch] $NoOpen
)

$ErrorActionPreference = 'Stop'

function Resolve-ShardFile {
    param([string] $Value)

    $resolvedValue = [Environment]::ExpandEnvironmentVariables($Value.Trim('"'))
    $guid = [Guid]::Empty
    if ([Guid]::TryParse($resolvedValue, [ref] $guid)) {
        $resolvedValue = Join-Path (Join-Path $HOME 'Downloads') $guid.ToString()
    }

    if (-not (Test-Path -LiteralPath $resolvedValue)) {
        throw "Shard path does not exist: $resolvedValue"
    }

    $item = Get-Item -LiteralPath $resolvedValue
    if (-not $item.PSIsContainer) {
        if ($item.Extension -ne '.shard') {
            throw "Expected a shard directory, GUID, or .shard file: $resolvedValue"
        }
        return $item.FullName
    }

    $shardFiles = @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.shard')
    if ($shardFiles.Count -eq 0) {
        throw "No .shard file exists directly under: $($item.FullName)"
    }
    if ($shardFiles.Count -gt 1) {
        throw "Multiple .shard files exist under '$($item.FullName)'; pass the desired file path."
    }

    return $shardFiles[0].FullName
}

function Resolve-InspectorWorkspace {
    param([string] $ExplicitRoot)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($ExplicitRoot) {
        $candidates.Add($ExplicitRoot)
    }

    $candidates.Add('C:\Fabric\Azure-Kusto-Service\Src\Engine\storage')

    $worktreeRoot = Join-Path $HOME 'OneDrive - Microsoft\Projects\copilot-worktrees\Azure-Kusto-Service'
    if (Test-Path -LiteralPath $worktreeRoot) {
        Get-ChildItem -LiteralPath $worktreeRoot -Directory |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                $candidates.Add((Join-Path $_.FullName 'Src\Engine\storage'))
            }
    }

    foreach ($candidate in $candidates) {
        $root = [Environment]::ExpandEnvironmentVariables($candidate)
        $manifest = Join-Path $root 'tools\shard_inspector\Cargo.toml'
        if (Test-Path -LiteralPath $manifest) {
            return (Get-Item -LiteralPath $root).FullName
        }
    }

    throw 'Could not find tools\shard_inspector. Open or restore the Azure-Kusto-Service "Shard artifact inspector" project session.'
}

$shardFile = Resolve-ShardFile -Value $Shard
$shardDirectory = Split-Path -Parent $shardFile
$temporaryFiles = @(Get-ChildItem -LiteralPath $shardDirectory -Recurse -File -Filter '.azDownload-*')
if ($temporaryFiles.Count -gt 0) {
    $relativePaths = $temporaryFiles |
        ForEach-Object { $_.FullName.Substring($shardDirectory.Length).TrimStart('\') }
    throw "Storage Explorer has not finalized these downloads:`n$($relativePaths -join "`n")"
}

$workspace = Resolve-InspectorWorkspace -ExplicitRoot $InspectorRoot
$shardId = [IO.Path]::GetFileNameWithoutExtension($shardFile)

if (-not $OutputPath) {
    $suffix = if ($IndexesOnly) { 'indexes' } else { 'shard-inspection' }
    $OutputPath = Join-Path (Join-Path $HOME 'Downloads') "$shardId-$suffix.json"
} else {
    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        [Environment]::ExpandEnvironmentVariables($OutputPath)
    )
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Push-Location $workspace
try {
    $jsonLines = @(
        & cargo run -p shard_inspector -- `
            $shardFile `
            --record-limit $RecordLimit `
            --term-limit $TermLimit `
            --posting-limit $PostingLimit `
            --json
    )
    if ($LASTEXITCODE -ne 0) {
        throw "shard_inspector failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

$json = $jsonLines -join [Environment]::NewLine
if ($IndexesOnly) {
    $report = $json | ConvertFrom-Json
    $json = ConvertTo-Json -InputObject @($report.inverted_indexes) -Depth 100
}

Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8

$generateHtml = -not $NoHtml
if ($generateHtml) {
    $htmlScript = Join-Path $PSScriptRoot 'New-KustoShardBTreeHtml.ps1'
    if (-not (Test-Path -LiteralPath $htmlScript)) {
        throw "HTML generator is missing: $htmlScript"
    }

    if (-not $HtmlOutputPath) {
        $HtmlOutputPath = [IO.Path]::ChangeExtension($OutputPath, '.html')
    }

    $generatedHtml = & $htmlScript `
        -JsonPath $OutputPath `
        -OutputPath $HtmlOutputPath `
        -NoOpen

    if (-not $NoOpen) {
        Start-Process -FilePath $generatedHtml
    }

    Write-Output $OutputPath
    Write-Output $generatedHtml
    return
}

if (-not $NoOpen) {
    $code = Get-Command code -ErrorAction SilentlyContinue
    if (-not $code) {
        throw "Created '$OutputPath', but the VS Code 'code' command is not available."
    }
    & $code.Source --reuse-window $OutputPath
}

Write-Output $OutputPath
