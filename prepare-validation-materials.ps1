<#
.SYNOPSIS
  One-shot preparation of all validation-site materials for a city.

.DESCRIPTION
  Given a GHSCI city configuration file (and assuming the GHSCI analysis for
  that city has already been run, with the ghsci + ghscic_postgis containers
  up), this script:

    1. generates the written validation report  (_validation_report.py)
    2. exports the validation map layers        (_export_validation_tiles.py)
    3. builds the three PMTiles archives        (build/build_tiles.sh)
    4. copies tiles + manifest + report into this validation-site folder
       under the city's slug, and registers the slug in index.html

  Run from the validation-site directory (or anywhere - paths are resolved
  relative to this script). Then review, git add/commit/push.

.PARAMETER Config
  The city configuration, one of:
    - a path relative to the GHSCI process dir, e.g. "data/Cycling/Minneapolis/Minneapolis.yml"
    - just the yml file name, e.g. "Minneapolis.yml" or "Minneapolis"
      (searched for under process/data/Cycling)

.EXAMPLE
  .\prepare-validation-materials.ps1 Minneapolis
.EXAMPLE
  .\prepare-validation-materials.ps1 "data/Cycling/Dar es Salaam/DarEsSalaam.yml"
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Config
)

$ErrorActionPreference = 'Stop'
$SiteDir = $PSScriptRoot
$ProcessDir = Resolve-Path (Join-Path $SiteDir '..\..\global-indicators\process')

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "!! $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------- resolve config
Step "Resolving city configuration"
$cfgRel = $null
if ($Config -match '[\\/]') {
  $candidate = Join-Path $ProcessDir ($Config -replace '/', '\')
  if (Test-Path $candidate) { $cfgRel = $Config -replace '\\', '/' }
} else {
  $name = $Config
  if ($name -notmatch '\.yml$') { $name = "$name.yml" }
  $hits = @(Get-ChildItem -Path (Join-Path $ProcessDir 'data\Cycling') -Recurse -Filter $name)
  if ($hits.Count -eq 1) {
    $full = $hits[0].FullName
    $cfgRel = $full.Substring("$ProcessDir".Length + 1) -replace '\\', '/'
  } elseif ($hits.Count -gt 1) {
    throw "Multiple configs named $name found under data/Cycling - pass the full relative path."
  }
}
if (-not $cfgRel) { throw "Could not locate configuration '$Config' under $ProcessDir\data\Cycling" }
$stem = [IO.Path]::GetFileNameWithoutExtension($cfgRel)
Write-Host "   config: $cfgRel"

# ---------------------------------------------------------------- preflight
$running = docker ps --format '{{.Names}}'
if ($LASTEXITCODE -ne 0) { throw 'docker is not available - is Docker Desktop running?' }
if ($running -notcontains 'ghsci') { throw 'The ghsci container is not running (start it with global-indicators.bat).' }

# find Git Bash explicitly: bare "bash" from PowerShell resolves to the WSL
# launcher (system32), which has no docker CLI unless WSL integration is on
$GitBash = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $GitBash) {
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notmatch 'system32') { $GitBash = $cmd.Source }
}
if (-not $GitBash) { throw 'Git Bash not found (install Git for Windows).' }

# ---------------------------------------------------------------- 1. report
Step "1/4 Generating validation report (this can take several minutes)"
docker exec ghsci /env/bin/python /home/ghsci/process/_validation_report.py $cfgRel
$reportOk = ($LASTEXITCODE -eq 0)
if (-not $reportOk) { Warn 'Report generation failed - continuing with tiles; report will be skipped.' }

# ---------------------------------------------------------------- 2. export layers
Step "2/4 Exporting validation map layers"
$exportOut = docker exec ghsci /env/bin/python /home/ghsci/process/_export_validation_tiles.py $cfgRel
if ($LASTEXITCODE -ne 0) { $exportOut | Write-Host; throw 'Layer export failed.' }
$exportOut | Write-Host
$slug = $null
foreach ($line in $exportOut) {
  if ($line -match '-> /tmp/validation_tiles/(\S+)') { $slug = $Matches[1]; break }
}
if (-not $slug) { throw 'Could not determine city slug from export output.' }
Write-Host "   slug: $slug"

# ---------------------------------------------------------------- 3. build tiles
Step "3/4 Building PMTiles archives"
# clear any stale copy so build_tiles.sh re-pulls the fresh export from the container
$work = Join-Path $SiteDir 'build\_work'
if (Test-Path (Join-Path $work $slug)) { Remove-Item -Recurse -Force (Join-Path $work $slug) }
Push-Location $SiteDir
try {
  & $GitBash ./build/build_tiles.sh $slug
  if ($LASTEXITCODE -ne 0) { throw 'Tile build failed.' }
} finally { Pop-Location }

# ---------------------------------------------------------------- 4. assemble site
Step "4/4 Copying materials into the validation site"
$tilesDir = Join-Path $SiteDir 'tiles'
Copy-Item (Join-Path $work "$slug.pmtiles") $tilesDir -Force
Copy-Item (Join-Path $work ($slug + '_lts.pmtiles')) $tilesDir -Force
Copy-Item (Join-Path $work ($slug + '_grid.pmtiles')) $tilesDir -Force
$manifestDir = Join-Path $tilesDir $slug
if (-not (Test-Path $manifestDir)) { New-Item -ItemType Directory -Path $manifestDir | Out-Null }
Copy-Item (Join-Path $work "$slug\manifest.json") $manifestDir -Force
Write-Host "   tiles/$slug.pmtiles, ${slug}_lts.pmtiles, ${slug}_grid.pmtiles, $slug/manifest.json"

$reportSrc = Join-Path $ProcessDir "data\_study_region_outputs\$stem\${stem}_cycling_validation_report.html"
if ($reportOk -and (Test-Path $reportSrc)) {
  Copy-Item $reportSrc (Join-Path $SiteDir "reports\$slug.html") -Force
  Write-Host "   reports/$slug.html"
} else {
  Warn "No validation report found at $reportSrc - the dashboard's report button will stay hidden for this city."
}

# register the slug in index.html CITY_SLUGS if not already present
$indexPath = Join-Path $SiteDir 'index.html'
$html = [IO.File]::ReadAllText($indexPath)
if ($html -match "const CITY_SLUGS = \[([^\]]*)\]") {
  if ($Matches[1] -notmatch "'$slug'") {
    $newList = "const CITY_SLUGS = [" + $Matches[1].TrimEnd() + ", '$slug'];"
    $html = $html -replace [regex]::Escape($Matches[0]), $newList.TrimEnd(';')
    [IO.File]::WriteAllText($indexPath, $html, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "   index.html: added '$slug' to CITY_SLUGS"
  } else {
    Write-Host "   index.html: '$slug' already registered"
  }
} else {
  Warn 'Could not find CITY_SLUGS in index.html - add the slug manually.'
}

Step "Done"
Write-Host @"
$stem is ready as '$slug'. Test locally (e.g. npx http-server . -p 8123), then publish:

  git add index.html "tiles/$slug*" "reports/$slug.html"
  git commit -m "Add/update $stem validation materials"
  git push origin main
"@
