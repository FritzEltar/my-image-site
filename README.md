# My Image Library

个人图片素材库，托管在 GitHub Pages 上的纯静态图库。

搜索、分类筛选、分页、点击放大、复制图片链接、深色模式全部在前端完成，
没有后端、没有构建步骤、没有第三方依赖，改完直接 push 就能更新。

---

## 目录结构

```
my-image-site/
├── index.html                     页面结构
├── style.css                      样式（含深色模式与响应式）
├── script.js                      图库逻辑（渲染 / 搜索 / 两级分类 / 分页 / 灯箱）
├── images.json                    图片清单 —— 由脚本自动生成，不要手改
├── .nojekyll                      告诉 GitHub Pages 不要跑 Jekyll
├── images/                        图片放这里，目录层级 = 分类层级
│   ├── README.txt
│   └── meta.json                  （可选）人工标题 / 标签，需自己创建
└── tools/
    ├── generate-manifest.ps1      扫描 images/ 生成 images.json
    ├── update-gallery.cmd         上面脚本的双击版
    ├── preview.mjs                本地预览服务器
    └── preview.cmd                上面脚本的双击版
```

---

## 分类逻辑（两级）

```
images/
├── 大图集1/          ← 一级分类：显示成第一行按钮
│   ├── 角色1/        ← 二级分类：选中大图集后，显示成第二行筛选
│   │   ├── 001.jpg
│   │   └── 002.jpg
│   └── 角色2/
└── 大图集2/
    ├── 角色1/
    └── 角色2/
```

- **第一行**永远显示 `全部 + 各个大图集`，右边带图片数量。
- 点某个大图集后，**第二行**才出现，显示该大图集下的小类别。
- 点最左边的「全部」回到所有大图集，第二行收起。
- 某个大图集下只有一种小类别时，第二行自动隐藏（留着没有意义）。
- 搜索会**同时匹配**一级分类、二级分类、标题、标签和文件名。

三级及以上也可以，第三层会合并进二级显示，例如
`images/大图集1/角色1/服装/a.jpg` → 一级「大图集1」、二级「角色1/服装」。

---

## 添加图片

1. 按上面的层级把图片放进 `images/`，例如：

   ```
   images/大图集1/角色1/001.jpg
   images/大图集1/角色2/002.png
   images/大图集2/角色1/003.webp
   ```

   文件夹名就是网站上显示的分类名，**随便改，改完重跑一次脚本即可**。
   直接丢在 `images/` 根目录的图片归入一级「未分类」。

2. 双击 `tools\update-gallery.cmd`（或在仓库目录运行
   `powershell -File tools\generate-manifest.ps1`）重新生成 `images.json`。

3. 提交并推送，网站即更新。

### 想让标题更好看？

默认标题是文件名去掉扩展名，所以 `001.jpg` 会显示成 `001`。
在 `images/meta.json` 里写覆盖信息即可（没有这个文件就自己新建一个）：

```json
{
  "大图集1/角色1/001.jpg": {
    "title": "雷电将军 立绘",
    "description": "绘画参考用",
    "tags": ["原神", "人物", "参考"]
  },
  "大图集2/角色1/屏幕截图(37).png": {
    "title": "Minecraft 服务器截图",
    "subcategory": "游戏场景"
  }
}
```

键是相对 `images/` 的路径。`title`、`description`、`tags`、`category`、
`subcategory` 都是可选的——不写就用文件夹名和文件名。
改完重新运行生成脚本即可，标签也参与搜索。

---

## 本地预览

`script.js` 用 `fetch` 读取 `images.json`，所以**直接双击 `index.html` 会因浏览器
安全策略而读取失败**，页面会提示「图片清单加载失败」。请用本地服务器预览：

**最简单的方式：双击 `tools\preview.cmd`**，它会启动服务器并自动打开浏览器。

也可以手动起服务：

```powershell
# 仓库自带的预览脚本（需要 Node.js）
node tools/preview.mjs

# 或者用 Python
python -m http.server 8000

# 或者用 npx
npx --yes serve -l 8000
```

然后打开 <http://127.0.0.1:8000>。改完代码刷新页面即可，服务器不用重启。

---

## 发布到 GitHub Pages

首次发布（在 GitHub 网页上操作，因为本机没装 `gh` CLI）：

1. 打开 <https://github.com/new>，仓库名填 **my-image-site**，
   选 **Public**（Pages 免费版需要公开仓库），**不要**勾选
   "Add a README file" / .gitignore / license —— 本地已经有内容了，保持空仓库。
2. 点 **Create repository**，然后复制页面上给出的地址。
3. 在本地仓库目录执行（把地址换成你自己的）：

   ```powershell
   cd D:\Github_repository\my-image-site
   git remote add origin https://github.com/FritzEltar/my-image-site.git
   git push -u origin main
   ```

4. 回到仓库页面 → **Settings** → 左侧 **Pages** →
   **Source** 选 `Deploy from a branch` →
   **Branch** 选 `main`、目录选 `/ (root)` → **Save**。
5. 等 1～2 分钟，站点地址是：

   ```
   https://fritzeltar.github.io/my-image-site/
   ```

之后每次更新只要三步：

```powershell
cd D:\Github_repository\my-image-site
git add .
git commit -m "添加新图片"
git push
```

---

## 几点限制与提醒

- **单文件 ≤ 100 MB**，超过会被 GitHub 直接拒绝推送；建议单张控制在 5 MB 内，
  网页加载才不至于太慢。
- 仓库建议保持在 1 GB 以内，GitHub Pages 站点也有 1 GB 软上限。
- 图片是公开的，别放私人照片或涉及隐私、版权问题的素材。
- 站点有大约 100 GB/月的流量软限制，个人图库远远用不到。
- 想换成自己的域名：在 `Settings → Pages → Custom domain` 填域名，
  再去域名商处加一条 CNAME 记录指向 `fritzeltar.github.io`。
- **改动 `tools\generate-manifest.ps1` 后请务必存成「UTF-8 带 BOM」。**
  本机只有 Windows PowerShell 5.1，它会把无 BOM 的 UTF-8 脚本当成 ANSI 读，
  导致里面的中文变成乱码、脚本直接报语法错误。用 VS Code 的话在右下角
  编码处选 `UTF-8 with BOM` 保存。

---

## 工作原理

- `index.html` 只提供骨架，两级分类按钮和图片网格都由 `script.js` 动态生成。
- 页面加载时 `fetch('images.json')` 拿到清单，按 `category` 聚合成第一行按钮；
  选中某个大图集后，再按 `subcategory` 聚合出第二行筛选。
- 过滤条件 = 一级分类 + 二级分类 + 关键词，最后做前端分页（每页 12 张）。
- 图片用 `loading="lazy"` 懒加载，滚动到才请求。
- 深色模式存 `localStorage`，首次访问跟随系统 `prefers-color-scheme`。
- 灯箱支持 `Esc` 关闭、`←` `→` 切换上一张 / 下一张、点遮罩关闭。
- `.nojekyll` 文件让 GitHub Pages 跳过 Jekyll 处理，避免下划线开头的
  文件名或目录被忽略，同时加快部署。
