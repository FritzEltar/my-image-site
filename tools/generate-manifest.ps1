<#
    generate-manifest.ps1
    ------------------------------------------------------------
    扫描 images/ 目录，生成网站读取的 images.json 清单。

    用法（在仓库根目录）：
        powershell -File tools\generate-manifest.ps1
      或双击 tools\update-gallery.cmd

    ------------------------------------------------------------
    目录层级 = 网站层级，共三级：

        images/全部/大图集1/角色1/001.jpg
               └大类┘└大图集┘└角色┘

      第 1 层  images/<大类>/            例如「全部」。以后想加新大类，
                                        直接建 images/<新大类>/ 即可
      第 2 层  <大类>/<大图集>/          网站的图集列表，每个图集一张封面
      第 3 层  <大图集>/<角色>/          图集内的分类（没有「全部」这一档）

    规则：
      · 图片直接放在大图集文件夹下（没有角色子文件夹）-> 归入「草稿箱」，
        用来放还没分类的图
      · 第 4 层及更深会合并进角色名，例如 角色1/服装 -> 角色 "角色1/服装"
      · 放在 images/ 根目录的图片 -> 大类「未分类」/ 大图集「未分类」
      · 文件名去掉扩展名后作为标题

    图集封面的确定顺序（先找到先用）：
      1) 大图集文件夹里的 cover.jpg / cover.png / _cover.* / 封面.*
         想换封面，直接替换这个文件即可（它不会被当成图片显示）
      2) images/meta.json 里该大图集的 "cover" 字段
      3) 该大图集里的第一张图

    images/meta.json（可选，不存在就跳过）：
      {
        "collections": {
          "全部/大图集1": { "name": "显示名", "cover": "角色1/001.jpg" }
        },
        "images": {
          "全部/大图集1/角色1/001.jpg": {
            "title": "雷电将军",
            "description": "官方立绘",
            "tags": ["原神", "参考"]
          }
        }
      }
      也兼容旧格式：顶层直接就是「图片路径 -> 属性」的映射。

    ------------------------------------------------------------
    缩略图：
      脚本会顺手给每张图生成一张小图，放在 thumbs/ 下（目录结构与
      images/ 保持一致，统一转成 .jpg）。网站网格和封面卡用缩略图，
      点开灯箱和下载仍然是原图。

      用的是 .NET 自带的 System.Drawing，不需要安装任何东西。
      缩略图比原图新时会自动跳过，所以重复运行很快。

      可调参数：
        -NoThumbs            只更新清单，不生成缩略图
        -ThumbWidth 600      缩略图最大宽度（默认 600）
        -ThumbQuality 82     缩略图 JPEG 质量（默认 82）

      注意：webp / avif / svg 这几种 System.Drawing 读不了，会自动
      跳过，这些图在网格里直接用原图（清单里 thumb 字段为空）。

    ------------------------------------------------------------
    资源版本号：
      GitHub Pages 对所有文件都发 Cache-Control: max-age=600，浏览器
      10 分钟内不会重新请求。改了 style.css / script.js 如果 URL 不变，
      访客就会一直看到旧样式（刷新也没用）。

      所以本脚本会按这两个文件的内容算一个短哈希，写进 index.html：

          <link rel="stylesheet" href="style.css?v=d4b40e2f">
          <script src="script.js?v=d4b40e2f"></script>

      内容一变版本号就变，浏览器必然重新拉取。不用手动维护。
#>

[CmdletBinding()]
param(
    # 图片目录（相对仓库根目录）
    [string]$ImagesDir = 'images',

    # 输出的清单文件名（相对仓库根目录）
    [string]$OutputFile = 'images.json',

    # 缩略图输出目录（相对仓库根目录）
    [string]$ThumbDir = 'thumbs',

    # 缩略图最大宽度（像素）。网格里一张卡片约 285px 宽，600 够 2 倍屏
    [int]$ThumbWidth = 600,

    # 缩略图 JPEG 质量（1-100）
    [int]$ThumbQuality = 82,

    # 只更新清单，不生成缩略图
    [switch]$NoThumbs
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$imagesPath = Join-Path $root $ImagesDir
$outputPath = Join-Path $root $OutputFile
$thumbRoot = Join-Path $root $ThumbDir

if (-not (Test-Path -LiteralPath $imagesPath)) {
    Write-Host "找不到图片目录：$imagesPath" -ForegroundColor Red
    exit 1
}

$extensions = @('.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif', '.bmp', '.svg')
# System.Drawing 读不了的格式，只能直接用小图代替缩略图
$thumbableExtensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp')
$coverNames = @('cover', '_cover', '封面')
$DRAFT = '草稿箱'
$UNCLASSIFIED = '未分类'

# ---------- 缩略图支持（.NET 自带的 System.Drawing，无需装任何东西）----------

$thumbsAvailable = $false
if (-not $NoThumbs) {
    try {
        Add-Type -AssemblyName System.Drawing
        $thumbsAvailable = $true
    }
    catch {
        Write-Host "无法加载 System.Drawing，本次跳过缩略图：$($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# 源图相对 images/ 的路径 -> 缩略图相对仓库的路径
$thumbMap = @{}
$thumbUsed = @{}      # 防止不同源图撞到同一个缩略图文件名
$thumbStats = @{ made = 0; skipped = 0; failed = 0; bytes = 0 }

function Get-ThumbRelPath($relFromImages) {
    $dir = Split-Path $relFromImages -Parent
    $base = [System.IO.Path]::GetFileNameWithoutExtension($relFromImages)

    $candidate = if ($dir) { Join-Path $ThumbDir (Join-Path $dir "$base.jpg") } else { Join-Path $ThumbDir "$base.jpg" }
    $candidate = $candidate -replace '\\', '/'

    # 同名不同扩展名（a.png 和 a.jpg）会撞车，撞了就带上原扩展名
    if ($thumbUsed.ContainsKey($candidate) -and $thumbUsed[$candidate] -ne $relFromImages) {
        $ext = [System.IO.Path]::GetExtension($relFromImages).TrimStart('.').ToLower()
        $candidate = if ($dir) { Join-Path $ThumbDir (Join-Path $dir "$base.$ext.jpg") } else { Join-Path $ThumbDir "$base.$ext.jpg" }
        $candidate = $candidate -replace '\\', '/'
    }
    $thumbUsed[$candidate] = $relFromImages
    return $candidate
}

function New-Thumbnail($sourcePath, $targetPath) {
    $img = $null; $bmp = $null; $gfx = $null
    try {
        $img = [System.Drawing.Image]::FromFile($sourcePath)

        $ratio = $ThumbWidth / $img.Width
        if ($ratio -gt 1) { $ratio = 1 }        # 不放大
        $w = [int][Math]::Max(1, [Math]::Round($img.Width * $ratio))
        $h = [int][Math]::Max(1, [Math]::Round($img.Height * $ratio))

        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        # 透明区域铺白，否则转 JPEG 会变黑
        $gfx.Clear([System.Drawing.Color]::White)
        $gfx.DrawImage($img, 0, 0, $w, $h)

        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }

        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1

        $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality, [int]$ThumbQuality)

        $bmp.Save($targetPath, $codec, $encParams)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($gfx) { $gfx.Dispose() }
        if ($bmp) { $bmp.Dispose() }
        if ($img) { $img.Dispose() }
    }
}

# 为一张图准备缩略图，成功后记进 $thumbMap
function Add-ThumbFor($relFromImages) {
    if (-not $thumbsAvailable) { return }

    # 已经处理过就跳过：封面和图片会是同一张，避免重复计数
    if ($thumbMap.ContainsKey($relFromImages)) { return }

    $ext = [System.IO.Path]::GetExtension($relFromImages).ToLower()
    if ($thumbableExtensions -notcontains $ext) { return }   # webp/avif/svg 跳过

    $thumbRel = Get-ThumbRelPath $relFromImages
    $sourceFull = Join-Path $imagesPath $relFromImages
    $targetFull = Join-Path $root $thumbRel

    # 增量：缩略图比原图新就跳过
    if (Test-Path -LiteralPath $targetFull) {
        $srcTime = (Get-Item -LiteralPath $sourceFull).LastWriteTimeUtc
        $dstTime = (Get-Item -LiteralPath $targetFull).LastWriteTimeUtc
        if ($dstTime -ge $srcTime) {
            $thumbMap[$relFromImages] = $thumbRel
            $thumbStats.skipped++
            $thumbStats.bytes += (Get-Item -LiteralPath $targetFull).Length
            return
        }
    }

    if (New-Thumbnail $sourceFull $targetFull) {
        $thumbMap[$relFromImages] = $thumbRel
        $thumbStats.made++
        $thumbStats.bytes += (Get-Item -LiteralPath $targetFull).Length
    }
    else {
        $thumbStats.failed++
        Write-Host ("  缩略图失败，将直接用原图：" + $relFromImages) -ForegroundColor Yellow
    }
}

function ConvertTo-TagArray($value) {
    if ($null -eq $value) { return @() }
    $raw = @()
    foreach ($v in @($value)) {
        $raw += ([string]$v) -split '[,，;；]'
    }
    return @($raw | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# ---------- 读取 meta.json ----------

$metaCollections = @{}
$metaImages = @{}

$metaPath = Join-Path $imagesPath 'meta.json'
if (Test-Path -LiteralPath $metaPath) {
    try {
        $raw = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $propNames = @($raw.PSObject.Properties.Name)

        if (($propNames -contains 'collections') -or ($propNames -contains 'images')) {
            if ($raw.collections) {
                foreach ($p in $raw.collections.PSObject.Properties) {
                    $metaCollections[($p.Name -replace '\\', '/').Trim('/')] = $p.Value
                }
            }
            if ($raw.images) {
                foreach ($p in $raw.images.PSObject.Properties) {
                    $metaImages[($p.Name -replace '\\', '/').Replace('images/', '').Trim('/')] = $p.Value
                }
            }
        }
        else {
            # 旧格式：顶层直接是「图片路径 -> 属性」
            foreach ($p in $raw.PSObject.Properties) {
                $metaImages[($p.Name -replace '\\', '/').Replace('images/', '').Trim('/')] = $p.Value
            }
        }

        Write-Host "已读取 meta.json（图集 $($metaCollections.Count) 条 / 图片 $($metaImages.Count) 条）" -ForegroundColor Cyan
    }
    catch {
        Write-Host "meta.json 解析失败，已忽略：$($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ---------- 扫描文件，建三级树 ----------

$files = Get-ChildItem -LiteralPath $imagesPath -Recurse -File |
    Where-Object { $extensions -contains $_.Extension.ToLower() } |
    Where-Object { $_.Name -notlike '.*' } |
    Where-Object { $coverNames -notcontains [System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLower() } |
    Sort-Object FullName

$tree = [ordered]@{}
$coverFiles = @{}
$count = 0

foreach ($file in $files) {
    $relFromImages = $file.FullName.Substring($imagesPath.Length).TrimStart('\', '/') -replace '\\', '/'
    $segments = @($relFromImages -split '/' | Where-Object { $_ })
    if ($segments.Count -lt 1) { continue }

    $name = $segments[$segments.Count - 1]
    $dirs = @()
    if ($segments.Count -gt 1) {
        $dirs = @($segments[0..($segments.Count - 2)])
    }

    # 第 1 层 = 大类，第 2 层 = 大图集，第 3 层起 = 角色
    $group = if ($dirs.Count -ge 1) { $dirs[0] } else { $UNCLASSIFIED }
    $collection = if ($dirs.Count -ge 2) { $dirs[1] } else { $UNCLASSIFIED }
    $role = if ($dirs.Count -ge 3) { ($dirs[2..($dirs.Count - 1)]) -join '/' } else { $DRAFT }

    $relPath = "$ImagesDir/$relFromImages"
    $title = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $description = ''
    $tags = @()

    if ($metaImages.ContainsKey($relFromImages)) {
        $m = $metaImages[$relFromImages]
        if ($m.title) { $title = [string]$m.title }
        if ($m.description) { $description = [string]$m.description }
        if ($m.tags) { $tags = ConvertTo-TagArray $m.tags }
    }

    if (-not $tree.Contains($group)) { $tree[$group] = [ordered]@{} }
    if (-not $tree[$group].Contains($collection)) { $tree[$group][$collection] = [ordered]@{} }
    if (-not $tree[$group][$collection].Contains($role)) {
        $tree[$group][$collection][$role] = New-Object System.Collections.Generic.List[object]
    }

    # 先生成缩略图，再写进条目
    Add-ThumbFor $relFromImages
    $thumbRel = ''
    if ($thumbMap.ContainsKey($relFromImages)) { $thumbRel = $thumbMap[$relFromImages] }

    $tree[$group][$collection][$role].Add([pscustomobject][ordered]@{
        file        = $relPath
        thumb       = $thumbRel
        title       = $title
        description = $description
        tags        = $tags
    }) | Out-Null

    $count++
}

# ---------- 找封面文件（cover.jpg / _cover.png / 封面.webp）----------

foreach ($group in @($tree.Keys)) {
    foreach ($collection in @($tree[$group].Keys)) {
        $dir = Join-Path $imagesPath (Join-Path $group $collection)
        if (-not (Test-Path -LiteralPath $dir)) { continue }

        $found = Get-ChildItem -LiteralPath $dir -File |
            Where-Object { $extensions -contains $_.Extension.ToLower() } |
            Where-Object { $coverNames -contains [System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLower() } |
            Select-Object -First 1

        if ($found) {
            $rel = $found.FullName.Substring($imagesPath.Length).TrimStart('\', '/') -replace '\\', '/'
            $coverFiles["$group/$collection"] = "$ImagesDir/$rel"
            Add-ThumbFor $rel      # 封面也要缩略图，它在卡片里也是小图
        }
    }
}

# ---------- 组装 JSON 结构 ----------

$groupsOut = New-Object System.Collections.Generic.List[object]
$totalImages = 0

foreach ($group in @($tree.Keys | Sort-Object)) {
    $collectionsOut = New-Object System.Collections.Generic.List[object]
    $groupImages = 0
    $groupCover = ''
    $groupCoverThumb = ''

    foreach ($collection in @($tree[$group].Keys | Sort-Object)) {
        $rolesOut = New-Object System.Collections.Generic.List[object]
        $collectionImages = 0
        $firstImage = ''
        $firstDraftImage = ''

        # 角色排序：普通角色按名称，草稿箱永远排最后
        $sorted = @($tree[$group][$collection].Keys | Sort-Object)
        $roleNames = @($sorted | Where-Object { $_ -ne $DRAFT })
        if ($sorted -contains $DRAFT) { $roleNames += $DRAFT }

        foreach ($role in $roleNames) {
            $list = $tree[$group][$collection][$role]
            if ($list.Count -eq 0) { continue }

            # 回退封面优先用正式角色的第一张，草稿箱只作为兜底
            if ($role -eq $DRAFT) {
                if (-not $firstDraftImage) { $firstDraftImage = $list[0].file }
            }
            else {
                if (-not $firstImage) { $firstImage = $list[0].file }
            }

            $rolesOut.Add([pscustomobject][ordered]@{
                name       = $role
                imageCount = $list.Count
                images     = $list.ToArray()
            }) | Out-Null

            $collectionImages += $list.Count
        }

        if ($collectionImages -eq 0) { continue }

        $key = "$group/$collection"
        $cover = ''
        if ($coverFiles.ContainsKey($key)) {
            $cover = $coverFiles[$key]
        }
        elseif ($metaCollections.ContainsKey($key) -and $metaCollections[$key].cover) {
            $c = ([string]$metaCollections[$key].cover) -replace '\\', '/'
            if ($c -match '^images/') {
                $cover = $c
            }
            else {
                $cover = "$ImagesDir/$group/$collection/$($c.TrimStart('/'))"
            }
        }
        else {
            if ($firstImage) { $cover = $firstImage } else { $cover = $firstDraftImage }
        }

        # 封面在卡片里也是小图，同样给它一张缩略图
        $coverRel = ''
        if ($cover -match "^$([regex]::Escape($ImagesDir))/(.+)$") { $coverRel = $matches[1] }
        if ($coverRel -and (Test-Path -LiteralPath (Join-Path $imagesPath $coverRel))) {
            Add-ThumbFor $coverRel
        }
        $coverThumb = ''
        if ($coverRel -and $thumbMap.ContainsKey($coverRel)) { $coverThumb = $thumbMap[$coverRel] }

        $displayName = $collection
        if ($metaCollections.ContainsKey($key) -and $metaCollections[$key].name) {
            $displayName = [string]$metaCollections[$key].name
        }

        $collectionsOut.Add([pscustomobject][ordered]@{
            name       = $displayName
            path       = $key
            cover      = $cover
            coverThumb = $coverThumb
            imageCount = $collectionImages
            roles      = $rolesOut.ToArray()
        }) | Out-Null

        $groupImages += $collectionImages
        if (-not $groupCover) { $groupCover = $cover }
        if (-not $groupCoverThumb) { $groupCoverThumb = $coverThumb }
    }

    if ($collectionsOut.Count -eq 0) { continue }

    $groupsOut.Add([pscustomobject][ordered]@{
        name            = $group
        cover           = $groupCover
        coverThumb      = $groupCoverThumb
        collectionCount = $collectionsOut.Count
        imageCount      = $groupImages
        collections     = $collectionsOut.ToArray()
    }) | Out-Null

    $totalImages += $groupImages
}

# ---------- 清理孤儿缩略图 ----------
# 图片被删除或改名后，thumbs/ 里会留下对不上号的旧文件。
# 不清掉的话它们会一直跟着仓库走，越积越多。

$orphansRemoved = 0

if ($thumbsAvailable -and (Test-Path -LiteralPath $thumbRoot)) {
    $expected = @{}
    foreach ($key in $thumbMap.Keys) {
        $full = Join-Path $root ($thumbMap[$key] -replace '/', '\')
        $expected[$full] = $true
    }

    Get-ChildItem -LiteralPath $thumbRoot -Recurse -File | ForEach-Object {
        if (-not $expected.ContainsKey($_.FullName)) {
            Remove-Item -LiteralPath $_.FullName -Force
            $orphansRemoved++
        }
    }

    # 顺手删掉空目录
    Get-ChildItem -LiteralPath $thumbRoot -Recurse -Directory |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force
            }
        }
}

if ($groupsOut.Count -eq 0) {
    $json = '[]'
}
else {
    $payload = [pscustomobject][ordered]@{
        version = 2
        groups  = $groupsOut.ToArray()
    }

    # PS 5.1 无法序列化 List[object]；结构嵌套很深，-Depth 必须给足
    $json = ConvertTo-Json -InputObject $payload -Depth 20

    # 5.1 会把非 ASCII 输出成 \uXXXX 转义，这里手工还原成可读字符
    # （不用 [regex]::Replace 的脚本块重载：5.1 不支持 ScriptBlock -> MatchEvaluator）
    $sb = New-Object System.Text.StringBuilder
    $last = 0
    foreach ($m in [regex]::Matches($json, '\\u([0-9a-fA-F]{4})')) {
        [void]$sb.Append($json.Substring($last, $m.Index - $last))
        [void]$sb.Append([char][Convert]::ToInt32($m.Groups[1].Value, 16))
        $last = $m.Index + $m.Length
    }
    [void]$sb.Append($json.Substring($last))
    $json = $sb.ToString()
}

# 必须写成 UTF-8 无 BOM，否则浏览器 fetch + JSON.parse 会报错
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outputPath, $json, $utf8NoBom)

# ---------- 给 style.css / script.js 打版本号 ----------
# GitHub Pages 对所有文件都下发 Cache-Control: max-age=600，
# 浏览器 10 分钟内不会重新请求。如果改了 CSS/JS 而 URL 不变，
# 访客就会一直看到旧样式（刷也没用）。这里按内容算一个短哈希拼在
# URL 后面，内容一变 URL 就变，浏览器必然重新拉取。

$indexPath = Join-Path $root 'index.html'
$assetVersion = ''

if (Test-Path -LiteralPath $indexPath) {
    $combined = ''
    foreach ($asset in @('style.css', 'script.js')) {
        $assetPath = Join-Path $root $asset
        if (Test-Path -LiteralPath $assetPath) {
            $combined += [System.IO.File]::ReadAllText($assetPath, [System.Text.Encoding]::UTF8)
        }
    }

    if ($combined) {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $assetVersion = ([System.BitConverter]::ToString(
            $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($combined))) -replace '-', '').Substring(0, 8).ToLower()
        $md5.Dispose()

        $html = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
        $updated = $html -replace 'href="style\.css(\?v=[0-9a-f]+)?"', "href=`"style.css?v=$assetVersion`""
        $updated = $updated -replace 'src="script\.js(\?v=[0-9a-f]+)?"', "src=`"script.js?v=$assetVersion`""

        if ($updated -ne $html) {
            [System.IO.File]::WriteAllText($indexPath, $updated, $utf8NoBom)
        }
    }
}

Write-Host ""
Write-Host "已生成清单：$outputPath" -ForegroundColor Green
Write-Host "共 $totalImages 张图片 / $($groupsOut.Count) 个大类" -ForegroundColor Green
if ($assetVersion) {
    Write-Host "资源版本号：style.css / script.js -> ?v=$assetVersion" -ForegroundColor Green
}

foreach ($g in $groupsOut) {
    Write-Host ""
    Write-Host ("  【{0}】{1} 个图集，{2} 张图" -f $g.name, $g.collectionCount, $g.imageCount) -ForegroundColor Cyan
    foreach ($c in $g.collections) {
        Write-Host ("    - {0}（{1} 张）封面: {2}" -f $c.name, $c.imageCount, (Split-Path $c.cover -Leaf))
        foreach ($r in $c.roles) {
            Write-Host ("        . {0}: {1} 张" -f $r.name, $r.imageCount)
        }
    }
}

if ($totalImages -gt 0) {
    Write-Host ""
    Write-Host "提示：换图集封面 = 往该图集文件夹放一个 cover.jpg；改标题/标签 = 编辑 images\meta.json" -ForegroundColor DarkGray
}

# ---------- 缩略图统计 ----------

if ($thumbsAvailable) {
    $madeText = "新生成 $($thumbStats.made) 张"
    if ($thumbStats.skipped -gt 0) { $madeText += "，复用 $($thumbStats.skipped) 张" }
    $sizeText = "{0:N0} KB" -f ($thumbStats.bytes / 1KB)

    Write-Host ""
    Write-Host "缩略图（$ThumbDir/）：$madeText，合计 $sizeText" -ForegroundColor Green
    if ($orphansRemoved -gt 0) {
        Write-Host "  清理了 $orphansRemoved 个已失效的旧缩略图（图片被删或改名留下的）" -ForegroundColor Green
    }
    if ($thumbStats.failed -gt 0) {
        Write-Host "  有 $($thumbStats.failed) 张生成失败，这些图会直接用原图显示" -ForegroundColor Yellow
    }
    Write-Host "  网格和封面用小图，点开看 / 下载仍是原图。" -ForegroundColor DarkGray
}
elseif (-not $NoThumbs) {
    Write-Host ""
    Write-Host "本次未生成缩略图。" -ForegroundColor Yellow
}
