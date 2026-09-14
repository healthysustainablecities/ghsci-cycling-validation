<#
  Re-run prepare-validation-materials.ps1 for every city currently published on the
  validation site.

  Pass -ReportOnly to rebuild just the written reports (e.g. after a change to
  subprocesses/_cycling_validation_report.py that does not affect the data): the tiles, manifests and
  route samples are left exactly as they are.

  DarEsSalaamCustom is deliberately excluded: its study region database no longer
  exists, so it could not be re-run, and it has been withdrawn from CITY_SLUGS.
  HelsinkiOsmDefault is also excluded: it is a sensitivity configuration that is not
  published on the site (running the driver for it would register a new slug).
  Minneapolis runs from Minneapolis.yml (slug minneapolis) as of 13 Sep 2026: every city
  is now the urban portion of an administrative boundary under the shared GHSL UCDB R2024A
  definition of urban, and Minneapolis-Urban (slug minneapolis_urban, whose boundary was a
  Census urban area) is superseded.  Earlier, Minneapolis-Urban was omitted from this list
  when first built by hand, which is how its report came to be copied into reports/ but
  never committed -- so the site showed no report for that city.
  DarEsSalaam is excluded as of 14 Aug 2026: its database was dropped and rebuilt on
  11 Aug under a changed no_cycle (pedestrian/footway/path re-added) and the run
  stopped after _11_neighbourhood_analysis, so it has no cycling accessibility or
  aggregation results to report on. It needs analysis.py finished and then a FULL
  materials run -- its published tiles and routes are stale against the new network
  too, not just its report -- so pass it explicitly rather than relying on this list.

  Logs one file per city under _rerun_logs/ and keeps going if a city fails, so one
  bad region does not abandon the rest.
#>
param(
  # Defaults to every published site city; pass a subset to resume after a failure.
  [string[]]$Configs = @(
    # Built from a char escape rather than a literal umlaut: this file has no BOM,
    # so Windows PowerShell 5.1 decodes it as ANSI and a literal 'ü' arrives as
    # 'Ã¼', which no longer matches the directory on disk.
    "data/Cycling/W$([char]0xFC)rzburg/W$([char]0xFC)rzburg.yml"
    'data/Cycling/Turin/Turin.yml'
    'data/Cycling/Suzhou/Suzhou.yml'
    'data/Cycling/Curitiba/Curitiba.yml'
    'data/Cycling/Chennai/Chennai.yml'
    'data/Cycling/Barcelona/Barcelona.yml'
    'data/Cycling/Tarragona/Tarragona.yml'
    'data/Cycling/Valencia/Valencia.yml'
    'data/Cycling/Helsinki/Helsinki.yml'
    'data/Cycling/MexicoCity/MexicoCityProper.yml'
    'data/Cycling/Melbourne/Melbourne.yml'
    'data/Cycling/Minneapolis/Minneapolis.yml'
    'data/Cycling/Dar es Salaam/DarEsSalaam.yml'
  ),
  # Rebuild only the written report for each city (skips layer export, route export
  # and tile build).  Passed straight through to prepare-validation-materials.ps1.
  [switch]$ReportOnly
)
$ErrorActionPreference = 'Continue'
$SiteDir = $PSScriptRoot
$LogDir = Join-Path $SiteDir '_rerun_logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

$configs = $Configs

$results = @()
foreach ($cfg in $configs) {
  $stem = [IO.Path]::GetFileNameWithoutExtension($cfg)
  $log = Join-Path $LogDir "$stem.log"
  Write-Host "=== $stem : $(Get-Date -Format HH:mm:ss)"
  $extra = @{}
  if ($ReportOnly) { $extra['ReportOnly'] = $true }
  # try/catch, not just $ErrorActionPreference: prepare-validation-materials.ps1 sets
  # its own 'Stop' and uses throw, and a terminating error from a called script
  # propagates and would abandon the remaining cities despite 'Continue' here.
  $ok = $false
  try {
    # stdout to a file only; do NOT use 2>&1 around native docker calls in PS 5.1,
    # which turns their stderr into terminating NativeCommandError records
    & (Join-Path $SiteDir 'prepare-validation-materials.ps1') -Config $cfg @extra > $log
    $ok = $?
  } catch {
    $_.Exception.Message | Out-File -FilePath $log -Append -Encoding utf8
  }
  if ($ok) { Write-Host "    OK" } else { Write-Host "    FAILED (see $log)" }
  $results += [pscustomobject]@{ City = $stem; Ok = $ok }
}

Write-Host "`n=== summary ==="
$results | ForEach-Object { Write-Host ("  {0,-20} {1}" -f $_.City, $(if ($_.Ok) { 'OK' } else { 'FAILED' })) }
Write-Host "ALL DONE"
