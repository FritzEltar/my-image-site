# My Image Library

个人图片素材库，托管在 GitHub Pages 上的纯静态图库。

**单页应用，不会开新网页。** 所有层级切换都靠前端视图 + URL hash
（`#/全部/大图集1/角色1`），浏览器的前进 / 后退键可以直接用，
刷新页面也能停在原来的位置。

---

## 目录结构

```
my-image-site/
├── index.html                     页面骨架
├── style.css                      样式（含深色模式与响应式）
├── script.js                      图库逻辑（hash 路由 / 三层导航 / 灯箱）
├── images.json                    图片清单 —— 由脚本自动生成，不要手改
├── .nojekyll                      告诉 GitHub Pages 不要跑 Jekyll
├── images/                        图片放这里，目录层级 = 网站层级
│   ├── README.txt
│   └── meta.json                  （可选）封面 / 标题 / 标签，需自己创建
├── thumbs/                        缩略图 —— 由脚本自动生成，不要手改
└── tools/
    ├── generate-manifest.ps1      扫描 images/ 生成 images.json
    ├── update-gallery.cmd         上面脚本的双击版
    ├── preview.mjs                本地预览服务器
    └── preview.cmd                上面脚本的双击版
```

---

## 分类逻辑（三级）

```
images/
└── 全部/                    ← 第 1 级：大类
    ├── 大图集1/             ← 第 2 级：大图集（网站上是封面卡片）
    │   ├── 角色1/           ← 第 3 级：角色
    │   │   ├── 001.jpg
    │   │   └── 002.jpg
    │   ├── 角色2/
    │   └── 001.jpg          ← 直接放在图集下的图 -> 自动进「草稿箱」
    └── 大图集2/
        ├── 角色1/
        └── 草稿箱/          ← 也可以手动建这个文件夹
```

### 网站上怎么走

| 层级 | 页面 | 说明 |
|---|---|---|
| 第 1 级 | **大类列表** | 每个大类一张封面卡。**只有一个大类时会自动进入，不显示这一层** |
| 第 2 级 | **图集封面列表** | 每个图集只用一张固定的封面图，下面写着「几张图 · 几个角色」 |
| 第 3 级 | **角色页签 + 图片** | 顶部是角色切换，下面是对应图片 |

- 顶部有**面包屑**：`全部图库 / 全部 / 大图集1`，点中间任一段都能跳回去。
- **没有「全部」这一档筛选**：不展示所有图片，必须落到具体的角色（或草稿箱）才看得到图。
- **草稿箱**排在角色页签最后一位，用来放还没分类的图。

### 未来扩展

想加新的大类，直接在 `images/` 下建文件夹：

```
images/
├── 全部/          ← 现有
└── 新大类/        ← 建好这个文件夹，网站首页就会自动变成大类列表
    └── 图集A/
        └── 角色1/
```

---

## 图集封面

每个图集的封面按这个顺序确定，**先找到先用**：

1. **图集文件夹里的 `cover.jpg`**（也支持 `cover.png` / `_cover.*` / `封面.*`）
   —— 想换封面，直接替换这个文件即可。它不会被当成图片显示在列表里。
2. `images/meta.json` 里该图集的 `cover` 字段
3. 该图集里正式角色的**第一张图**（草稿箱里的图只作兜底，不会优先当封面）

---

## 缩略图（自动生成，已开启）

你的原图很大（最大一张 6.9 MB / 4096×3072），网格里一张卡片却只有 285px 宽。
所以生成脚本会**顺手给每张图做一张小图**放进 `thumbs/`：

```
images/全部/大图集1/角色1/大图集截图.png     6.9 MB   ← 原图，点开才加载
thumbs/全部/大图集1/角色1/大图集截图.jpg      50 KB   ← 网格/封面用这张
```

- **网格和封面卡用缩略图，点开灯箱和下载仍是原图**，画质不受影响。
- 缩略图最长边 600px、JPEG 质量 82（约为卡片宽度的 2 倍，高清屏也不糊）。
- 缩略图比原图新时自动跳过，所以重复运行很快；删掉 `thumbs/` 就会全部重做。
- 用的是 .NET 自带的 `System.Drawing`，**不需要安装任何东西**。
- `webp` / `avif` / `svg` 这几种读不了，会自动跳过，这些图直接用原图显示。
- 缩略图**必须一起提交**，否则线上看到的是原图。
- **删图或给文件夹改名后，脚本会自动清理失效的旧缩略图**
  （会打印一行「清理了 N 个已失效的旧缩略图」），不用手动去 `thumbs/` 里翻。

效果（当前图库）：

| 页面 | 之前 | 现在 |
|---|---|---|
| 图集列表页（2 张封面） | 12.08 MB | **0.15 MB**（80 倍） |
| 图集内页 · 一个角色 3 张 | 7.13 MB | **0.18 MB**（40 倍） |
| 整个图库缩略图合计 | — | 0.42 MB |

想调整：

```powershell
# 只更新清单，不做缩略图
powershell -File tools\generate-manifest.ps1 -NoThumbs

# 想要更清晰的缩略图（体积会大一些）
powershell -File tools\generate-manifest.ps1 -ThumbWidth 900 -ThumbQuality 88
```

---

## 添加图片

1. 按层级把图片放进 `images/`，例如：

   ```
   images/全部/大图集1/角色1/001.jpg
   images/全部/大图集1/角色2/002.png
   images/全部/大图集2/角色1/003.webp
   ```

   文件夹名就是网站上显示的名字，**随便改，改完重跑一次脚本即可**。

2. 双击 `tools\update-gallery.cmd`（或运行
   `powershell -File tools\generate-manifest.ps1`）重新生成 `images.json`。

3. 提交并推送，网站即更新。

### 想让标题更好看？

默认标题是文件名去掉扩展名。在 `images/meta.json` 里写覆盖信息即可
（没有这个文件就自己新建一个）：

```json
{
  "collections": {
    "全部/大图集1": {
      "name": "原神立绘",
      "cover": "角色1/001.jpg"
    }
  },
  "images": {
    "全部/大图集1/角色1/001.jpg": {
      "title": "雷电将军 立绘",
      "description": "官方立绘",
      "tags": ["原神", "人物", "参考"]
    }
  }
}
```

- `collections` 的键是 `大类/图集`，`cover` 可以写相对图集文件夹的路径，
  也可以写完整的 `images/...` 路径。
- `images` 的键是相对 `images/` 的完整路径。
- 顶层的旧写法（直接就是「图片路径 → 属性」）也仍然兼容。

### 搜索

搜索框只在图集内部出现，**默认搜当前图集的所有角色**（不只是当前页签），
命中的图片会跨角色一起列出来，标题、标签、描述、文件名都会匹配。

---

## 本地预览

`script.js` 用 `fetch` 读取 `images.json`，所以**直接双击 `index.html`
会因浏览器安全策略而读取失败**。请用本地服务器预览：

**最简单：双击 `tools\preview.cmd`**，会自动起服务器并打开浏览器。

也可以手动起服务：

```powershell
node tools/preview.mjs          # 仓库自带（需要 Node.js）
python -m http.server 8000      # 或者用 Python
npx --yes serve -l 8000         # 或者用 npx
```

然后打开 <http://127.0.0.1:8000>。

---

## 发布到 GitHub Pages

首次发布（在 GitHub 网页上操作）：

1. 打开 <https://github.com/new>，仓库名填 **my-image-site**，
   选 **Public**，**不要**勾选 "Add a README file" 等（本地已有内容）。
2. 点 **Create repository**，然后：

   ```powershell
   cd D:\Github_repository\my-image-site
   git remote add origin https://github.com/FritzEltar/my-image-site.git
   git push -u origin main
   ```

3. 仓库页面 → **Settings** → 左侧 **Pages** → Source 选
   `Deploy from a branch` → Branch 选 `main`、目录选 `/ (root)` → **Save**。

站点地址：<https://fritzeltar.github.io/my-image-site/>

之后每次更新：

```powershell
cd D:\Github_repository\my-image-site
git add .
git commit -m "更新图库"
git push
```

推送后等 1~2 分钟自动部署完成。

---

## 更新后看不到变化？（缓存问题）

GitHub Pages 给**所有**文件都下发 `Cache-Control: max-age=600`，
意思是「10 分钟内别再来问我要」。直接后果：

- 改完 `style.css` / `script.js` 推上去，访客的浏览器还在用旧的缓存文件，
  **按 F5 也未必有用**，看起来就像"根本没更新"。

这个坑已经用**资源版本号**填掉了：生成脚本会按 `style.css` + `script.js`
的内容算一个短哈希，写进 `index.html`：

```html
<link rel="stylesheet" href="style.css?v=d4b40e2f">
<script src="script.js?v=d4b40e2f"></script>
```

内容一变，版本号就变，URL 就变，浏览器必然重新下载。**你什么都不用管**，
每次双击 `update-gallery.cmd` 都会自动维护。

如果哪次还是看到旧画面，按 **Ctrl + Shift + R**（强制刷新）一次即可。
实在不行就用无痕窗口打开，或者临时加个参数：
`https://fritzeltar.github.io/my-image-site/?v=1`

---

## 字体

正文用的是 **git-scm.com 的同款字体栈**：

```css
font-family: Adelle, "Roboto Slab", "DejaVu Serif", Georgia,
             "Times New Roman", "Microsoft YaHei", sans-serif;
```

git-scm.com 本身没有加载任何 web font，正文就是这个栈。本机没装
Adelle / Roboto Slab / DejaVu Serif，所以英文落在 **Georgia** 上 ——
和 git-scm.com 在你机器上的显示完全一致（实测两者渲染宽度都是 590.28px）。

这几个西文字体都没有中文字形，所以**中文会自动回退到微软雅黑**，
中英混排不会出现方框或宋体。

想换字体就改 `style.css` 最上面 `body` 里的 `font-family`。

---

## 页脚致谢

页脚第二行是本站的搭建者标记，和 "Powered by GitHub Pages" **并排在同一行**，
中间用一道横杠隔开，标记在右边：

```
Powered by GitHub Pages  —  🐋 Built with DeepSeek
```

标记是一条鲸鱼（DeepSeek 的标志）加一句 `Built with DeepSeek`。平时是低调的
暖灰，鼠标悬停时鲸鱼和链接会变成 DeepSeek 的品牌蓝 `#4d6bfe`。

它是内联 SVG（`index.html` 里 `.credit` 那一段），不额外请求文件；
深色 / 浅色模式的配色都单独适配过。不想要就删掉
`index.html` 页脚里的 `.credit` 和 `.footer-sep` 两段。

---

## 目录里那个测试集

`images/全部/大图集1/abcdefghijklmn/` 是**故意放的占位测试集**，
用来验证角色页签能容纳多长的英文名（14 个字母，页签宽约 132px，
不换行不截断）。不需要了可以删掉：

```powershell
Remove-Item 'images\全部\大图集1\abcdefghijklmn' -Recurse
# 然后双击 tools\update-gallery.cmd
```

---

## 几点限制与提醒

- **单文件 ≤ 100 MB**，超过会被 GitHub 直接拒绝推送。原图大一点没关系
  （网页只加载缩略图），但单张建议别超过 20 MB。
- 仓库建议保持在 1 GB 以内，GitHub Pages 站点也有 1 GB 软上限。
  缩略图只占几百 KB，不用担心。
- 图片是公开的，别放私人照片或涉及隐私、版权问题的素材。
- **本机 git 走代理**：这台机器上 git 已配置
  `http.proxy = http://127.0.0.1:7897`（只配在本仓库）。
  代理软件必须开着，否则 `git push` 会报 `Connection was reset`。
  想撤销：`git config --unset http.proxy`。
- **改动 `tools\generate-manifest.ps1` 后，最好存成「UTF-8 带 BOM」。**
  本机只有 Windows PowerShell 5.1，它会把无 BOM 的 UTF-8 脚本当 ANSI 读，
  导致里面的中文变成乱码、脚本直接报语法错误。
  **不过不用担心**：双击 `tools\update-gallery.cmd` 时它会自动检测并补回 BOM
  （会打印一行 `[fix] re-added UTF-8 BOM`），所以即使忘了也不会出问题。
  只有直接 `powershell -File tools\generate-manifest.ps1` 时才需要自己注意。

---

## 工作原理

- `images.json` 是三级嵌套清单：`groups → collections → roles → images`，
  每个图片条目带 `file`（原图）和 `thumb`（缩略图）两个路径。
- `script.js` 把 URL hash 解析成 `大类 / 图集 / 角色` 三段，据此切换视图；
  改 hash 会触发 `hashchange`，所以浏览器前进后退天然可用。
- 路由里的非法层级会自动回退到上一层（比如手工输入了不存在的角色名）。
- 第 1 级只有一个大类时，首页直接进入它，省掉一次没有意义的点击。
- 网格和图集封面用 `thumb` / `coverThumb`，灯箱和下载用 `file`
  （缩略图万一缺失会自动回退到原图）。
- 图片用 `loading="lazy"` 懒加载；图集封面优先用 `cover.*` 文件。
- 深色模式存 `localStorage`，首次访问跟随系统 `prefers-color-scheme`。
- 灯箱支持 `Esc` 关闭、`←` `→` 在**当前筛选结果**里翻页、点遮罩关闭。
- `.nojekyll` 让 GitHub Pages 跳过 Jekyll 处理，避免下划线开头的文件被忽略。
