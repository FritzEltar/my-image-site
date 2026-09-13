<#
    generate-manifest.ps1
    ------------------------------------------------------------
    扫描 images/ 目录，生成网站读取的 images.json 清单。

    用法（在仓库根目录）：
        pwsh -File tools\generate-manifest.ps1
      或双击 tools\update-gallery.cmd

    规则：
      · images/yuanshen/001.jpg        -> 分类 "yuanshen"
      · images/001.jpg                 -> 分类 "未分类"
      · images/动物/猫/001.jpg         -> 分类 "动物/猫"（支持多级）
      · 文件名去掉扩展名后作为标题
      · 若存在 images/meta.json，其中的 title / description / tags /
        category 会覆盖自动生成的值。格式示例：
          {
            "yuanshen/001.jpg": {
              "title": "雷电将军",
              "description": "官方立绘",
              "tags": ["原神", "参考"]
            }
          }
#>

[CmdletBinding()]
param(
    # 图片目录（相对仓库根目录）
    [string]$ImagesDir = 'images',

    # 输出的清单文件名（相对仓库根目录）
    [string]$OutputFile = 'images.json'
)

$ErrorActionPreference = 'Stop'

# 以脚本所在位置推导仓库根目录，保证在任何工作目录下都能正确运行
$root = Split-Path -Parent $PSScriptRoot
$imagesPath = Join-Path $root $ImagesDir
$outputPath = Join-Path $root $OutputFile

if (-not (Test-Path -LiteralPath $imagesPath)) {
    Write-Host "找不到图片目录：$imagesPath" -ForegroundColor Red
    exit 1
}

$extensions = @('.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif', '.bmp', '.svg')

# 读取可选的 meta.json（标题等人工信息）
$metaPath = Join-Path $imagesPath 'meta.json'
$meta = @{}
if (Test-Path -LiteralPath $metaPath) {
    try {
        $metaJson = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $metaJson.PSObject.Properties) {
            # 允许写成 "yuanshen/001.jpg" 或 "images/yuanshen/001.jpg"
            $key = $prop.Name -replace '\\', '/' -replace '^\.?/?images/', ''
            $meta[$key] = $prop.Value
        }
        Write-Host "已读取 meta.json（$($meta.Count) 条覆盖信息）" -ForegroundColor Cyan
    }
    catch {
        Write-Host "meta.json 解析失败，已忽略：$($_.Exception.Message)" -ForegroundColor Yellow
    }
}

$files = Get-ChildItem -LiteralPath $imagesPath -Recurse -File |
    Where-Object { $extensions -contains $_.Extension.ToLower() } |
    Where-Object { $_.Name -notlike '.*' } |
    Sort-Object FullName

# 标签既支持 JSON 数组，也支持 "a, b, c" 这样的字符串，统一成字符串数组
function ConvertTo-TagArray($value) {
    if ($null -eq $value) { return @() }
    $raw = @()
    foreach ($v in @($value)) {
        $raw += ([string]$v) -split '[,，;；]'
    }
    return @($raw | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

$entries = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    $relFromImages = $file.FullName.Substring($imagesPath.Length).TrimStart('\', '/') -replace '\\', '/'
    $relPath = "$ImagesDir/$relFromImages"

    # 分类 = 相对 images/ 的子目录；直接放在根目录则归为“未分类”
    $dir = $file.DirectoryName.Substring($imagesPath.Length).TrimStart('\', '/') -replace '\\', '/'
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = '未分类' }

    $title = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $description = ''
    $tags = @()
    $category = $dir

    if ($meta.ContainsKey($relFromImages)) {
        $m = $meta[$relFromImages]
        if ($m.title) { $title = [string]$m.title }
        if ($m.description) { $description = [string]$m.description }
        if ($m.category) { $category = [string]$m.category }
        if ($m.tags) { $tags = ConvertTo-TagArray $m.tags }
    }

    # 用 PSCustomObject 而不是裸的 [ordered]@{}：
    # OrderedDictionary 的键不是属性，Group-Object category 会得到空名字。
    $entries.Add([pscustomobject][ordered]@{
        file        = $relPath
        title       = $title
        category    = $category
        description = $description
        tags        = $tags
    }) | Out-Null
}

if ($entries.Count -eq 0) {
    $json = '[]'
}
else {
    # 注意：必须用 .ToArray() 转成普通数组。
    # Windows PowerShell 5.1 的 ConvertTo-Json 无法序列化
    # System.Collections.Generic.List[object]（会报 "Argument types do not match"），
    # 而且 @($list) 并不会把它展开成数组。
    $json = ConvertTo-Json -InputObject $entries.ToArray() -Depth 5

    # Windows PowerShell 5.1 会把非 ASCII 字符输出成 \uXXXX 转义，
    # 这里手工还原成原始字符，让 images.json 保持可读。
    # （不用 [regex]::Replace 的脚本块重载：5.1 不支持把 ScriptBlock 转成 MatchEvaluator）
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
Write-Host "共 $($entries.Count) 张图片" -ForegroundColor Green

if ($entries.Count -gt 0) {
    $entries | Group-Object category |
        Sort-Object Count -Descending |
        ForEach-Object { Write-Host ("  {0,-24} {1} 张" -f $_.Name, $_.Count) }
    Write-Host ""
    Write-Host "提示：想改标题/加标签，编辑 images\meta.json 后重新运行本脚本。" -ForegroundColor DarkGray
}
