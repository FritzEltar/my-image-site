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
#>

[CmdletBinding()]
param(
    # 图片目录（相对仓库根目录）
    [string]$ImagesDir = 'images',

    # 输出的清单文件名（相对仓库根目录）
    [string]$OutputFile = 'images.json'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$imagesPath = Join-Path $root $ImagesDir
$outputPath = Join-Path $root $OutputFile

if (-not (Test-Path -LiteralPath $imagesPath)) {
    Write-Host "找不到图片目录：$imagesPath" -ForegroundColor Red
    exit 1
}

$extensions = @('.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif', '.bmp', '.svg')
$coverNames = @('cover', '_cover', '封面')
$DRAFT = '草稿箱'
$UNCLASSIFIED = '未分类'

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

    $tree[$group][$collection][$role].Add([pscustomobject][ordered]@{
        file        = $relPath
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

        $displayName = $collection
        if ($metaCollections.ContainsKey($key) -and $metaCollections[$key].name) {
            $displayName = [string]$metaCollections[$key].name
        }

        $collectionsOut.Add([pscustomobject][ordered]@{
            name       = $displayName
            path       = $key
            cover      = $cover
            imageCount = $collectionImages
            roles      = $rolesOut.ToArray()
        }) | Out-Null

        $groupImages += $collectionImages
        if (-not $groupCover) { $groupCover = $cover }
    }

    if ($collectionsOut.Count -eq 0) { continue }

    $groupsOut.Add([pscustomobject][ordered]@{
        name            = $group
        cover           = $groupCover
        collectionCount = $collectionsOut.Count
        imageCount      = $groupImages
        collections     = $collectionsOut.ToArray()
    }) | Out-Null

    $totalImages += $groupImages
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

Write-Host ""
Write-Host "已生成清单：$outputPath" -ForegroundColor Green
Write-Host "共 $totalImages 张图片 / $($groupsOut.Count) 个大类" -ForegroundColor Green

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
