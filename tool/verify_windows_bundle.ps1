param(
  [Parameter(Mandatory = $true)]
  [string] $BundlePath
)

$manifestPath = Join-Path $BundlePath 'data\flutter_assets\NativeAssetsManifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Native assets manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$assets = $manifest.'native-assets'.windows_x64
$assetProperties = @($assets.PSObject.Properties)
$missing = @(
  $assetProperties |
    ForEach-Object { $_.Value[1] } |
    Where-Object { -not (Test-Path -LiteralPath (Join-Path $BundlePath $_) -PathType Leaf) }
)

if ($missing.Count -gt 0) {
  throw "Windows bundle is missing native assets: $($missing -join ', ')"
}

Write-Output "Verified $($assetProperties.Count) Windows native assets."
