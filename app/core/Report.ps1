# Scan report export (JSON for tools, HTML for people).

function ConvertTo-HDHtml {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Export-HDReport {
    param($Scan, [string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLower()
    if ($ext -eq '.json') {
        # Plain hashtables + [object[]]: PowerShell 5.1 otherwise serializes some arrays as {"value":[...],"Count":n}.
        $items = foreach ($i in $Scan.Items) {
            [ordered]@{
                Id = $i.Id; Category = $i.Category; Kind = $i.Kind; Risk = $i.Risk; State = $i.State
                Selectable = $i.Selectable; Checked = $i.Checked; Scope = $i.Scope
                Title = $i.Title; Desc = $i.Desc; Tradeoff = $i.Tradeoff
                Details = [object[]]@($i.Details); Warnings = [object[]]@($i.Warnings); Notes = [object[]]@($i.Notes)
            }
        }
        $obj = [ordered]@{ App = $Scan.App; Version = $Scan.Version; ScannedAt = $Scan.ScannedAt; Machine = $Scan.Machine; Items = [object[]]@($items) }
        $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
        return
    }

    $cats = 'warn', 'apps', 'ads', 'startup', 'oem', 'xbox', 'privacy', 'system', 'security', 'notdone'
    $m = $Scan.Machine
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Heartnet Debloat - laporan scan</title>
<style>
:root{--ink:#2E1E1F;--navy:#3F5F80;--wing:#761D31;--slate:#708DAB;--slate-light:#DCE7F1;--paper:#F4F8FA;--amber:#E3A33B;--muted:#3B4650}
body{margin:0;background:var(--paper);color:var(--ink);font-family:"Segoe UI",system-ui,sans-serif;line-height:1.5}
header{background:#fff;color:var(--ink);padding:20px 24px;border-bottom:3px solid var(--ink)}
header h1{margin:0;font-size:24px}header p{margin:4px 0 0;color:var(--navy);font-size:14px}
main{max-width:920px;margin:0 auto;padding:16px}
h2{font-size:18px;margin:28px 0 10px}
.card{background:#fff;border:2px solid var(--ink);border-radius:12px;box-shadow:3px 3px 0 var(--ink);padding:10px 14px;margin:0 0 12px}
.card h3{margin:0;font-size:15px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.badge{border:1.5px solid var(--ink);border-radius:999px;padding:0 10px;font-size:12px;font-weight:600}
.Low{background:var(--navy);color:#fff}.Optional{background:var(--amber)}.Experimental{background:var(--wing);color:#fff}.Info{background:#fff}.Warning{background:var(--amber)}
.state{font-size:12px;color:var(--muted);margin-left:auto}
.card p{margin:6px 0 0;font-size:14px}.trade{color:var(--muted)}
.warn{color:var(--wing);font-weight:600}
ul{margin:6px 0 0;padding-left:20px;font-size:12px;color:var(--muted);font-family:Consolas,monospace;word-break:break-all}
</style></head><body><header><h1>Heartnet Debloat - laporan scan</h1>
<p>$(ConvertTo-HDHtml ("{0} {1} | {2} {3} (build {4}) | {5}" -f $m.Manufacturer, $m.Model, $m.OS, $m.DisplayVersion, $m.Build, $Scan.ScannedAt))</p></header><main>
"@)
    foreach ($c in $cats) {
        $items = @($Scan.Items | Where-Object { $_.Category -eq $c -and $_.State -ne 'NotPresent' })
        if (-not $items.Count) { continue }
        [void]$sb.Append("<h2>$(ConvertTo-HDHtml (T "cat.$c"))</h2>")
        foreach ($i in $items) {
            [void]$sb.Append("<div class='card'><h3>$(ConvertTo-HDHtml $i.Title)<span class='badge $($i.Risk)'>$(ConvertTo-HDHtml (T "risk.$($i.Risk)"))</span>")
            if ($i.Kind -eq 'Action') { [void]$sb.Append("<span class='state'>$(ConvertTo-HDHtml (T "state.$($i.State)"))</span>") }
            [void]$sb.Append("</h3><p>$(ConvertTo-HDHtml $i.Desc)</p><p class='trade'>$(ConvertTo-HDHtml $i.Tradeoff)</p>")
            foreach ($w in $i.Warnings) { [void]$sb.Append("<p class='warn'>$(ConvertTo-HDHtml $w)</p>") }
            foreach ($n in $i.Notes) { [void]$sb.Append("<p class='trade'><i>$(ConvertTo-HDHtml $n)</i></p>") }
            if ($i.Details.Count) { [void]$sb.Append('<ul>' + (($i.Details | ForEach-Object { "<li>$(ConvertTo-HDHtml $_)</li>" }) -join '') + '</ul>') }
            [void]$sb.Append('</div>')
        }
    }
    [void]$sb.Append("<p style='font-size:12px;color:var(--muted)'>Heartnet Debloat $($Scan.Version). Scan ini hanya membaca, tidak ada yang diubah.</p></main></body></html>")
    [IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
}

# Report of one run (apply + any undo), written next to manifest.json.
function Export-HDRunReport {
    param($Manifest, [string]$Path)
    $m = $Manifest
    $sb = New-Object System.Text.StringBuilder
    $rp = $m.RestorePoint
    $rpText = if (-not $rp) { T 'run.rp.none' } elseif ($rp.Status -eq 'Created') { T 'run.rp.ok' $rp.Sequence } else { T 'rp.failed' $rp.Reason }
    [void]$sb.Append(@"
<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Heartnet Debloat - $(ConvertTo-HDHtml $m.RunId)</title>
<style>
:root{--ink:#2E1E1F;--navy:#3F5F80;--wing:#761D31;--paper:#F4F8FA;--amber:#E3A33B;--muted:#3B4650}
body{margin:0;background:var(--paper);color:var(--ink);font-family:"Segoe UI",system-ui,sans-serif;line-height:1.5}
header{background:#fff;padding:20px 24px;border-bottom:3px solid var(--ink)}header h1{margin:0;font-size:22px}header p{margin:4px 0 0;color:var(--muted);font-size:14px}
main{max-width:960px;margin:0 auto;padding:16px}
.card{background:#fff;border:2px solid var(--ink);border-radius:12px;box-shadow:3px 3px 0 var(--ink);padding:10px 14px;margin:0 0 12px}
.card h3{margin:0;font-size:15px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.badge{border:1.5px solid var(--ink);border-radius:999px;padding:0 10px;font-size:12px;font-weight:600}
.Success{background:var(--navy);color:#fff}.Skipped{background:#fff}.Failed{background:var(--wing);color:#fff}.Undone{background:var(--amber)}
.reason{color:var(--wing);font-size:13px;margin:4px 0 0}
table{border-collapse:collapse;width:100%;margin-top:6px;font-size:12px;font-family:Consolas,monospace}
td,th{border-top:1px solid #d5dde3;padding:3px 6px;text-align:left;vertical-align:top;word-break:break-all}th{font-family:"Segoe UI",sans-serif;color:var(--muted)}
</style></head><body><header><h1>Heartnet Debloat - $(ConvertTo-HDHtml (T 'run.report.title' $m.RunId))</h1>
<p>$(ConvertTo-HDHtml ('{0} {1} | {2} | {3}' -f $m.Machine.Manufacturer, $m.Machine.Model, $m.User, $m.CreatedAt))</p>
<p>$(ConvertTo-HDHtml $rpText)</p></header><main>
"@)
    $mb = $m.Metrics
    if ($mb -and $mb.Before) {
        $later = $mb.Later
        [void]$sb.Append("<div class='card'><h3>$(ConvertTo-HDHtml (T 'metrics.title'))</h3><table><tr><th></th><th>$(T 'metrics.col.before')</th><th>$(T 'metrics.col.after')</th><th>+/-</th>")
        if ($later) { [void]$sb.Append("<th>$(ConvertTo-HDHtml (T 'metrics.col.later' $later.UptimeMin))</th><th>+/-</th>") }
        [void]$sb.Append('</tr>')
        $rowsAfter = @(Get-HDMetricRows $mb.Before $mb.After)
        $rowsLater = if ($later) { @(Get-HDMetricRows $mb.Before $later) } else { @() }
        for ($k = 0; $k -lt $rowsAfter.Count; $k++) {
            $ra = $rowsAfter[$k]
            [void]$sb.Append(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td>' -f (ConvertTo-HDHtml $ra.Label), $ra.A, $ra.B, $ra.Delta))
            if ($later) { $rl = $rowsLater[$k]; [void]$sb.Append(('<td>{0}</td><td>{1}</td>' -f $rl.B, $rl.Delta)) }
            [void]$sb.Append('</tr>')
        }
        [void]$sb.Append("</table><p class='reason' style='color:var(--muted)'>$(ConvertTo-HDHtml (T 'metrics.note'))</p></div>")
    }
    foreach ($i in @($m.Items)) {
        [void]$sb.Append("<div class='card'><h3>$(ConvertTo-HDHtml $i.Title)<span class='badge $($i.Result)'>$(ConvertTo-HDHtml (T "result.$($i.Result)"))</span>")
        if ($i.UndoState -in 'Undone', 'Partial') { [void]$sb.Append("<span class='badge Undone'>$(ConvertTo-HDHtml (T "undo.state.$($i.UndoState)"))</span>") }
        [void]$sb.Append('</h3>')
        foreach ($r in @($i.Reasons)) { [void]$sb.Append("<p class='reason'>$(ConvertTo-HDHtml $r)</p>") }
        if (@($i.Units).Count) {
            [void]$sb.Append("<table><tr><th>$(T 'run.col.target')</th><th>$(T 'run.col.before')</th><th>$(T 'run.col.after')</th><th>$(T 'run.col.result')</th><th>$(T 'run.col.undo')</th></tr>")
            foreach ($u in @($i.Units)) {
                $undo = if ($u.Undo) { '{0} {1}' -f (T "result.$($u.Undo.Result)"), $u.Undo.Reason } else { '' }
                [void]$sb.Append(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td></tr>' -f (ConvertTo-HDHtml $u.Label),
                        (ConvertTo-HDHtml (Format-HDState $u.Before)), (ConvertTo-HDHtml (Format-HDState $u.After)),
                        (ConvertTo-HDHtml ((T "result.$($u.Result)") + ' ' + $u.Reason)), (ConvertTo-HDHtml $undo)))
            }
            [void]$sb.Append('</table>')
        }
        [void]$sb.Append('</div>')
    }
    [void]$sb.Append("<p style='font-size:12px;color:var(--muted)'>$(ConvertTo-HDHtml (T 'run.report.folder' $m.Folder))</p></main></body></html>")
    [IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
}

function Format-HDState {
    # Short one-line text of a handler state (Before/After, as read back from JSON) for reports and the UI.
    param($State)
    if ($null -eq $State) { return '' }
    $props = if ($State -is [System.Collections.IDictionary]) { @($State.Keys | ForEach-Object { @{ Name = $_; Value = $State[$_] } }) }
             else { @($State.PSObject.Properties | ForEach-Object { @{ Name = $_.Name; Value = $_.Value } }) }
    $parts = foreach ($p in $props) {
        $v = $p.Value
        if ($v -is [array]) {
            $v = '[' + (@($v | ForEach-Object {
                        if ($_ -and $_.FullName) { $_.FullName } elseif ($_ -and $_.DisplayName) { $_.DisplayName } else { [string]$_ } }) -join ', ') + ']'
        }
        '{0}={1}' -f $p.Name, $v
    }
    return (@($parts) -join '; ')
}
