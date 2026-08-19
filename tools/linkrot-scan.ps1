# The Workbench — archive link-rot scanner (2026-08-13)
# Harvests all live posts, checks video embeds via oEmbed and links via HTTP.
# Output: linkrot-inventory.json (raw), linkrot-results.json (checked), linkrot-progress.txt
$ErrorActionPreference = 'Continue'
$root = 'C:\AL\Blog-Modernization'
$prog = Join-Path $root 'linkrot-progress.txt'
Set-Content $prog "started $(Get-Date -Format o)"

# --- auth ---
$cfg = Get-Content (Join-Path $root 'docwatch\blogger-client.json') -Raw | ConvertFrom-Json
$tok = Get-Content (Join-Path $root 'docwatch\blogger-token.json') -Raw | ConvertFrom-Json
$fresh = Invoke-RestMethod -Uri 'https://oauth2.googleapis.com/token' -Method Post -Body @{
    refresh_token = $tok.refresh_token; client_id = $cfg.client_id
    client_secret = $cfg.client_secret; grant_type = 'refresh_token' }
$H = @{ Authorization = "Bearer $($fresh.access_token)" }

# --- phase 1: harvest all live posts ---
$posts = @()
$url = 'https://www.googleapis.com/blogger/v3/blogs/5285970135510371565/posts?status=LIVE&fetchBodies=true&maxResults=100'
while ($url) {
    $r = Invoke-RestMethod -Uri $url -Headers $H
    $posts += @($r.items)
    Add-Content $prog "harvested $($posts.Count) posts"
    $url = if ($r.nextPageToken) { "https://www.googleapis.com/blogger/v3/blogs/5285970135510371565/posts?status=LIVE&fetchBodies=true&maxResults=100&pageToken=$($r.nextPageToken)" } else { $null }
}

# --- phase 2: extract videos + links per post ---
$videos = [System.Collections.Generic.List[object]]::new()
$links  = [System.Collections.Generic.List[object]]::new()
foreach ($p in $posts) {
    $c = $p.content
    # iframe embeds
    foreach ($m in [regex]::Matches($c, '<iframe[^>]*src="([^"]+)"')) {
        $src = $m.Groups[1].Value
        if ($src -match 'youtube(-nocookie)?\.com/embed/([A-Za-z0-9_-]{6,})') { $videos.Add(@{ kind='youtube'; vid=$Matches[2]; src=$src; postId=$p.id; postUrl=$p.url; postTitle=$p.title; postDate=$p.published.ToString('yyyy-MM-dd') }) }
        elseif ($src -match 'player\.vimeo\.com/video/(\d+)') { $videos.Add(@{ kind='vimeo'; vid=$Matches[1]; src=$src; postId=$p.id; postUrl=$p.url; postTitle=$p.title; postDate=$p.published.ToString('yyyy-MM-dd') }) }
        elseif ($src -match '^https?://') { $videos.Add(@{ kind='iframe-other'; vid=$src; src=$src; postId=$p.id; postUrl=$p.url; postTitle=$p.title; postDate=$p.published.ToString('yyyy-MM-dd') }) }
    }
    # legacy flash embeds (object/embed with /v/ID)
    foreach ($m in [regex]::Matches($c, '(?:<embed|<object)[^>]*(?:src|data)="([^"]*youtube[^"]*/v/([A-Za-z0-9_-]{6,})[^"]*)"') ) {
        $videos.Add(@{ kind='youtube-flash'; vid=$m.Groups[2].Value; src=$m.Groups[1].Value; postId=$p.id; postUrl=$p.url; postTitle=$p.title; postDate=$p.published.ToString('yyyy-MM-dd') })
    }
    # anchors
    foreach ($m in [regex]::Matches($c, '<a[^>]*href="(https?://[^"]+)"')) {
        $href = $m.Groups[1].Value -replace '&amp;', '&'
        if ($href -match 'blogger\.googleusercontent\.com|bp\.blogspot\.com') { continue } # image lightboxes
        $links.Add(@{ href=$href; postId=$p.id; postUrl=$p.url; postTitle=$p.title; postDate=$p.published.ToString('yyyy-MM-dd') })
    }
}
@{ videos = $videos; links = $links } | ConvertTo-Json -Depth 4 -Compress | Set-Content (Join-Path $root 'linkrot-inventory.json') -Encoding utf8
Add-Content $prog "extracted: $($videos.Count) video embeds, $($links.Count) links ($((@($links.href | Sort-Object -Unique)).Count) unique)"

# --- phase 3: check videos via oEmbed ---
$videoResults = @{}
$uniqueVids = $videos | Group-Object { "$($_.kind)|$($_.vid)" }
$i = 0
foreach ($g in $uniqueVids) {
    $i++
    $v = $g.Group[0]
    $status = 'unknown'
    try {
        if ($v.kind -like 'youtube*') {
            $null = Invoke-RestMethod -Uri "https://www.youtube.com/oembed?url=https%3A//www.youtube.com/watch%3Fv%3D$($v.vid)&format=json" -TimeoutSec 20
            $status = 'alive'
        } elseif ($v.kind -eq 'vimeo') {
            $null = Invoke-RestMethod -Uri "https://vimeo.com/api/oembed.json?url=https%3A//vimeo.com/$($v.vid)" -TimeoutSec 20
            $status = 'alive'
        } else {
            try { $resp = Invoke-WebRequest -Uri $v.src -Method Head -TimeoutSec 20 -UseBasicParsing -MaximumRedirection 5; $status = "alive" }
            catch { $code = $_.Exception.Response.StatusCode.value__; $status = if ($code) { "http-$code" } else { 'unreachable' } }
        }
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        $status = if ($code) { "dead-$code" } else { 'unreachable' }
    }
    $videoResults[$g.Name] = $status
    if ($i % 20 -eq 0) { Add-Content $prog "videos checked: $i / $($uniqueVids.Count)" }
}
Add-Content $prog "videos done: $($uniqueVids.Count) unique checked"

# --- phase 4: check unique links in parallel ---
$uniqueLinks = @($links.href | Sort-Object -Unique)
Add-Content $prog "checking $($uniqueLinks.Count) unique links..."
$linkResults = $uniqueLinks | ForEach-Object -ThrottleLimit 12 -Parallel {
    $u = $_
    $status = ''
    try {
        $resp = Invoke-WebRequest -Uri $u -Method Head -TimeoutSec 15 -UseBasicParsing -MaximumRedirection 8 -ErrorAction Stop
        $status = "ok-$($resp.StatusCode)"
    } catch {
        $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($code -eq 405 -or $code -eq 403 -or $code -eq 400) {
            # some servers refuse HEAD; retry GET
            try { $resp = Invoke-WebRequest -Uri $u -Method Get -TimeoutSec 15 -UseBasicParsing -MaximumRedirection 8 -ErrorAction Stop; $status = "ok-$($resp.StatusCode)" }
            catch { $c2 = $null; try { $c2 = $_.Exception.Response.StatusCode.value__ } catch {}; $status = if ($c2) { "http-$c2" } else { 'unreachable' } }
        } elseif ($code) { $status = "http-$code" }
        else {
            $msg = $_.Exception.Message
            $status = if ($msg -match 'No such host|The remote name could not be resolved') { 'dns-dead' } elseif ($msg -match 'timed out|timeout') { 'timeout' } else { 'unreachable' }
        }
    }
    [PSCustomObject]@{ url = $u; status = $status }
}
$resultsMap = @{}
foreach ($lr in $linkResults) { $resultsMap[$lr.url] = $lr.status }
@{ videoResults = $videoResults; linkResults = $resultsMap } | ConvertTo-Json -Depth 3 -Compress | Set-Content (Join-Path $root 'linkrot-results.json') -Encoding utf8
$dead = @($linkResults | Where-Object { $_.status -match '^(http-4|dns-dead)' }).Count
Add-Content $prog "done $(Get-Date -Format o): links checked $($uniqueLinks.Count), hard-dead $dead"
