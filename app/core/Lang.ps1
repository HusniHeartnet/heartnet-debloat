# Localized strings. Indonesian is the base; other languages overlay it.

$script:HDStrings = @{}

function Initialize-HDLang {
    param([string]$Lang = 'id')
    $dir = Join-Path $PSScriptRoot '..\lang'
    $script:HDStrings = @{}
    $base = Import-PowerShellDataFile (Join-Path $dir 'id.psd1')
    foreach ($k in $base.Keys) { $script:HDStrings[$k] = $base[$k] }
    if ($Lang -ne 'id') {
        $file = Join-Path $dir "$Lang.psd1"
        if (Test-Path $file) {
            $over = Import-PowerShellDataFile $file
            foreach ($k in $over.Keys) { $script:HDStrings[$k] = $over[$k] }
        }
    }
}

function T {
    param([string]$Key, [object[]]$Args2)
    $s = $script:HDStrings[$Key]
    if ($null -eq $s) { return "[$Key]" }
    if ($Args2) { return ($s -f $Args2) }
    return $s
}

function Test-HDText { param([string]$Key) $script:HDStrings.ContainsKey($Key) }
