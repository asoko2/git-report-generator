param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$ProjectDirectory,
    
    [Parameter(Mandatory=$true, Position=1)]
    [string]$Username,
    
    [Parameter(Mandatory=$true, Position=2)]
    [string]$FromDate,
    
    [Parameter(Mandatory=$false, Position=3)]
    [string]$ToDate
)

$ErrorActionPreference = "Stop"

function Test-GitRepository {
    param([string]$Path)
    Push-Location $Path
    try {
        $null = git rev-parse --git-dir 2>&1
        return $LASTEXITCODE -eq 0
    } finally {
        Pop-Location
    }
}

function Test-DateFormat {
    param([string]$Date)
    return $Date -match '^\d{4}-\d{2}-\d{2}$'
}

function Format-GitTable {
    param([array]$CommitsData)
    if ($CommitsData.Count -eq 0) {
        return "No commits found for this period."
    }
    $numberedData = for ($i = 0; $i -lt $CommitsData.Count; $i++) {
        [PSCustomObject]@{
            No = $i + 1
            Commit = $CommitsData[$i].Subject
            Author = $CommitsData[$i].Author
            Date = $CommitsData[$i].Date
            Hash = $CommitsData[$i].Hash
        }
    }
    $maxNo = [Math]::Max(2, ($numberedData.No | Measure-Object -Maximum).Maximum.ToString().Length)
    $maxCommit = ($numberedData.Commit | Measure-Object -Maximum -Property Length).Maximum
    $maxCommit = [Math]::Max(6, $maxCommit)
    $maxAuthor = [Math]::Max(6, ($numberedData.Author | Measure-Object -Maximum -Property Length).Maximum)
    $maxDate = 10
    $maxHash = 7
    
    $table = New-Object System.Text.StringBuilder
    
    $headerNo = "No".PadRight($maxNo)
    $headerCommit = "Commit".PadRight($maxCommit)
    $headerAuthor = "Author".PadRight($maxAuthor)
    $headerDate = "Commit Date".PadRight($maxDate)
    $headerHash = "Hash".PadRight($maxHash)
    $null = $table.AppendLine("| $headerNo | $headerCommit | $headerAuthor | $headerDate | $headerHash |")
    
    $sepNo = "-" * $maxNo
    $sepCommit = "-" * $maxCommit
    $sepAuthor = "-" * $maxAuthor
    $sepDate = "-" * $maxDate
    $sepHash = "-" * $maxHash
    $null = $table.AppendLine("| $sepNo | $sepCommit | $sepAuthor | $sepDate | $sepHash |")
    
    foreach ($row in $numberedData) {
        $rowNo = $row.No.ToString().PadRight($maxNo)
        $rowCommit = $row.Commit.PadRight($maxCommit)
        $rowAuthor = $row.Author.PadRight($maxAuthor)
        $rowDate = $row.Date.PadRight($maxDate)
        $rowHash = $row.Hash.PadRight($maxHash)
        $null = $table.AppendLine("| $rowNo | $rowCommit | $rowAuthor | $rowDate | $rowHash |")
    }
    return $table.ToString().TrimEnd()
}

if ([string]::IsNullOrEmpty($ToDate)) {
    $ToDate = $FromDate
}

if (-not (Test-Path $ProjectDirectory -PathType Container)) {
    Write-Error "Error: Directory '$ProjectDirectory' does not exist"
    exit 1
}

if (-not (Test-GitRepository -Path $ProjectDirectory)) {
    Write-Error "Error: '$ProjectDirectory' is not a git repository"
    exit 1
}

if (-not (Test-DateFormat -Date $FromDate)) {
    Write-Error "Error: Invalid date format for FromDate. Use YYYY-MM-DD"
    exit 1
}

if (-not (Test-DateFormat -Date $ToDate)) {
    Write-Error "Error: Invalid date format for ToDate. Use YYYY-MM-DD"
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile = Join-Path $scriptDir "report_template.txt"

if (-not (Test-Path $templateFile)) {
    Write-Error "Error: Template file not found at $templateFile"
    exit 1
}

$template = Get-Content $templateFile -Raw
$since = "${FromDate}T00:00:00"
$until = "${ToDate}T23:59:59"
$projectName = Split-Path $ProjectDirectory -Leaf
$outputDir = Join-Path $scriptDir $projectName

if (-not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory | Out-Null
    Write-Host "Created output directory: $outputDir" -ForegroundColor Green
}

$reportFile = "report_${Username}_${FromDate}"
if ($FromDate -ne $ToDate) {
    $reportFile += "_to_${ToDate}"
}
$reportFile = Join-Path $outputDir "${reportFile}.txt"

if ($FromDate -eq $ToDate) {
    $dateRange = (Get-Date $FromDate).ToString("dd/MM/yyyy")
} else {
    $fromDisplay = (Get-Date $FromDate).ToString("dd/MM/yyyy")
    $toDisplay = (Get-Date $ToDate).ToString("dd/MM/yyyy")
    $dateRange = "$fromDisplay to $toDisplay"
}

Push-Location $ProjectDirectory
try {
    $gitLog = git log --author="$Username" --since="$since" --until="$until" --pretty=format:"%an|%s|%ad|%h" --date=short --all --regexp-ignore-case --reverse 2>&1
    if ($LASTEXITCODE -ne 0) {
        $commitsData = @()
    } else {
        $commitsData = $gitLog | Where-Object { $_ -notmatch '\|(Merge branch|Delete branch)\|' -and $_ -match '\|' } | ForEach-Object {
            $parts = $_ -split '\|'
            if ($parts.Count -eq 4) {
                [PSCustomObject]@{
                    Author = $parts[0]
                    Subject = $parts[1]
                    Date = $parts[2]
                    Hash = $parts[3]
                }
            }
        }
    }
} finally {
    Pop-Location
}

$matchedAuthors = ""
$totalCommits = 0

if ($commitsData.Count -gt 0) {
    $matchedAuthors = ($commitsData.Author | Select-Object -Unique) -join ', '
    $totalCommits = $commitsData.Count
    $commitsTable = Format-GitTable -CommitsData $commitsData
} else {
    Write-Warning "No commits found for author matching '$Username'"
    Write-Host "Searching for possible author names..." -ForegroundColor Yellow
    Push-Location $ProjectDirectory
    try {
        $allAuthors = git log --all --pretty=format:"%an" | Sort-Object -Unique
        $possibleAuthors = $allAuthors | Where-Object { $_ -match $Username }
        if ($possibleAuthors) {
            Write-Host "Found these author names containing '$Username':" -ForegroundColor Yellow
            $possibleAuthors | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "No authors found matching '$Username'" -ForegroundColor Yellow
            Write-Host "All authors in this repository:" -ForegroundColor Yellow
            $allAuthors | ForEach-Object { Write-Host "  $_" }
        }
    } finally {
        Pop-Location
    }
    $commitsTable = "No commits found for this period."
}

$reportContent = $template -replace '\{\{USERNAME\}\}', $Username -replace '\{\{PROJECT_NAME\}\}', $projectName -replace '\{\{DATE_RANGE\}\}', $dateRange -replace '\{\{FROM_DATE\}\}', $FromDate -replace '\{\{TO_DATE\}\}', $ToDate -replace '\{\{COMMITS\}\}', $commitsTable

[System.IO.File]::WriteAllText($reportFile, $reportContent, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Work report generated successfully!" -ForegroundColor Green
Write-Host "  File: $reportFile"
Write-Host "  Directory: $outputDir"
Write-Host "  Repository: $projectName"
if (-not [string]::IsNullOrEmpty($matchedAuthors)) {
    Write-Host "  Author(s) matched: $matchedAuthors"
}
Write-Host "  Search term: $Username"
Write-Host "  Period: $dateRange"
Write-Host "  Commits: $totalCommits"