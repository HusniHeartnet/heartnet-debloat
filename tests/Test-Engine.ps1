# Engine test: backup -> apply -> verify -> manifest -> undo, with a fake handler that only changes an
# in-memory "system". Nothing on the PC is touched; run folders go to a temp directory.
# Run: powershell -ExecutionPolicy Bypass -File tests\Test-Engine.ps1   (exit code 1 on failure)

$ErrorActionPreference = 'Stop'
$app = Join-Path (Split-Path $PSScriptRoot) 'app'
foreach ($f in 'Lang', 'Scan', 'Backup', 'Safety', 'Apply', 'Undo', 'Report', 'Metrics') { . (Join-Path $app "core\$f.ps1") }
foreach ($f in Get-ChildItem (Join-Path $app 'handlers') -Filter *.ps1) { . $f.FullName }
Initialize-HDLang 'en'

$fail = New-Object System.Collections.Generic.List[string]
$script:Checks = 0
function Check([bool]$Ok, [string]$Msg) { $script:Checks++; if (-not $Ok) { $fail.Add($Msg) } }

# ------------------------------------------------------------------ fake system + handler
$script:Sys = @{ a = 1; b = 0; stuck = 1; boom = 1 }
$script:SeenBackupOnDisk = $false
$script:HDHandlers['Fake'] = @{
    Side       = { param($t) 'User' }
    Expand     = { param($t) if ($script:Sys.ContainsKey($t.Name)) { @{ Type = 'Fake'; Key = "Fake:$($t.Name)"; Label = "fake $($t.Name)"; Name = $t.Name } } }
    Read       = { param($u) [ordered]@{ Value = $script:Sys[$u.Name] } }
    IsDone     = { param($u, $s) $s.Value -eq 0 }
    Backup     = { param($u, $before, $dir) @{ Note = "backup of $($u.Name)" } }
    Apply      = {
        param($u, $before, $backup, $dir)
        # The engine must have written the backup to disk before calling Apply.
        $r = Read-HDJson (Join-Path $dir 'results.json')
        $mine = @($r.Items | ForEach-Object { $_.Units } | Where-Object { $_.Key -eq $u.Key })[0]
        if ($mine -and $mine.Attempted -and $null -ne $mine.Before) { $script:SeenBackupOnDisk = $true }
        if ($u.Name -eq 'boom') { $script:Sys.boom = 7; throw 'kaboom' }
        if ($u.Name -ne 'stuck') { $script:Sys[$u.Name] = 0 }
    }
    Undo       = { param($u, $before, $backup, $dir) $script:Sys[$u.Name] = $before.Value }
    IsRestored = { param($u, $before, $now) $now.Value -eq $before.Value }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('hd-engine-' + [guid]::NewGuid().ToString('N'))
$runDir = Join-Path $tmp '20260101-000000'
[void][IO.Directory]::CreateDirectory($runDir)
try {
    $items = @(
        [pscustomobject]@{ Id = 'x.ok'; Title = 'OK item'; Targets = @(@{ T = 'Fake'; Name = 'a' }, @{ T = 'Fake'; Name = 'b' }, @{ T = 'Fake'; Name = 'missing' }) }
        [pscustomobject]@{ Id = 'x.stuck'; Title = 'Stuck item'; Targets = @(@{ T = 'Fake'; Name = 'stuck' }) }
        [pscustomobject]@{ Id = 'x.boom'; Title = 'Boom item'; Targets = @(@{ T = 'Fake'; Name = 'boom' }) }
    )
    $plan = [ordered]@{ App = 'Heartnet Debloat'; Version = 'test'; RunId = '20260101-000000'; CreatedAt = (Get-Date).ToString('s'); User = 'test'
                        Items = [object[]]@(@($items | ForEach-Object { [ordered]@{ Id = $_.Id; Title = $_.Title; Category = 'apps'; Risk = 'Low'; Sides = [object[]]@('User'); Policy = $false } }) +
                                            @([ordered]@{ Id = 'x.refused'; Title = 'Refused'; Category = 'apps'; Risk = 'Low'; Sides = [object[]]@('User'); Policy = $false })) }
    Save-HDJson -Path (Join-Path $runDir 'plan.json') -Object $plan

    # ---- apply
    $res = Invoke-HDApplySide -RunDir $runDir -Side 'User' -Items $items -Refused @{ 'x.refused' = 'blocked for test' }
    Save-HDRunState $runDir @{ Worker = 'Done'; UserSide = 'Done'; FinishedAt = (Get-Date).ToString('s') }
    Check $script:SeenBackupOnDisk 'backup was not on disk before Apply ran'
    Check ($script:Sys.a -eq 0) 'apply did not change a'
    $m = Update-HDManifest $runDir
    $byId = @{}; foreach ($i in $m.Items) { $byId[$i.Id] = $i }
    Check ($byId['x.ok'].Result -eq 'Success') "x.ok should be Success, got $($byId['x.ok'].Result)"
    Check (@($byId['x.ok'].Units | Where-Object { $_.Key -eq 'Fake:b' -and $_.Result -eq 'Skipped' }).Count -eq 1) 'already-done unit b should be Skipped'
    Check (@($byId['x.ok'].Units).Count -eq 2) 'missing target should not create a unit'
    Check ($byId['x.stuck'].Result -eq 'Failed') 'x.stuck should fail verify-after'
    Check ($byId['x.boom'].Result -eq 'Failed' -and ($byId['x.boom'].Reasons -join ' ') -match 'kaboom') 'x.boom should fail with the error text'
    Check ($byId['x.refused'].Result -eq 'Skipped' -and ($byId['x.refused'].Reasons -join ' ') -match 'blocked for test') 'refused item should be Skipped with its reason'
    Check ($byId['x.ok'].UndoState -eq 'Active') 'x.ok should be undoable'
    Check (Test-Path (Join-Path $runDir 'manifest.json')) 'manifest.json not written'
    Check (Test-Path (Join-Path $runDir 'report.html')) 'report.html not written'
    $u = @($byId['x.ok'].Units | Where-Object Key -eq 'Fake:a')[0]
    Check ($u.Before.Value -eq 1 -and $u.After.Value -eq 0) 'manifest should hold before=1 after=0 for a'

    # ---- undo one item, then everything
    $rec = Invoke-HDUndoSide -RunDir $runDir -Side 'User' -ItemIds @('x.boom') -JobId 'job1'
    Check ($script:Sys.boom -eq 1) 'undo of x.boom did not restore it'
    Check ($script:Sys.a -eq 0) 'undo of one item touched another item'
    $rec = Invoke-HDUndoSide -RunDir $runDir -Side 'User' -JobId 'job2'
    Check ($script:Sys.a -eq 1 -and $script:Sys.stuck -eq 1) 'undo all did not restore a/stuck'
    Check (-not ($rec.Units | Where-Object { $_.Item -eq 'x.boom' })) 'already undone unit was undone twice'
    Check (-not ($rec.Units | Where-Object { $_.Key -eq 'Fake:b' })) 'skipped (unchanged) unit must not be undone'
    $rec3 = Invoke-HDUndoSide -RunDir $runDir -Side 'User' -JobId 'job3'
    Check ($rec3.Units.Count -eq 0) 'third undo should have nothing left'
    $m = Update-HDManifest $runDir
    foreach ($i in $m.Items | Where-Object { $_.Id -ne 'x.refused' }) { Check ($i.UndoState -eq 'Undone') "$($i.Id) should be Undone, is $($i.UndoState)" }

    # ---- per-user changes cannot be undone by another account
    $file = Join-Path $runDir 'user\results.json'
    $json = [IO.File]::ReadAllText($file) -replace [regex]::Escape((Get-HDCurrentSid)), 'S-1-5-21-0-0-0-9999'
    [IO.File]::WriteAllText($file, $json)
    Get-ChildItem (Join-Path $runDir 'user') -Filter 'undo-*.json' | Remove-Item
    $script:Sys.a = 0
    $rec = Invoke-HDUndoSide -RunDir $runDir -Side 'User' -JobId 'job4'
    Check ($script:Sys.a -eq 0 -and @($rec.Units | Where-Object Result -eq 'Skipped').Count -eq $rec.Units.Count -and $rec.Units.Count -gt 0) 'undo from another account must be skipped'

    # ---- machine results are ignored unless owned by Administrators
    $mdir = Join-Path $runDir 'machine'
    [void][IO.Directory]::CreateDirectory($mdir)
    Copy-Item $file (Join-Path $mdir 'results.json')
    if (-not (Test-HDAdminOwned $mdir)) { Check ($null -eq (Read-HDSideResults $runDir 'Machine')) 'machine results written by a normal user must be ignored' }

    # ---- headless OtherUser refusal
    $res2 = Invoke-HDApplySide -RunDir (Join-Path $tmp 'r2') -Side 'User' -Items @($items[0]) -RefuseAll 'other account'
    Check ($res2.Items[0].Refused -eq 'other account' -and $script:Sys.a -eq 0) 'RefuseAll should skip without changing anything'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail.Count) {
    Write-Host "FAILED ($($fail.Count))" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "OK: engine apply / verify / manifest / undo ($script:Checks checks)" -ForegroundColor Green
