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

## 几点限制与提醒

- **单文件 ≤ 100 MB**，超过会被 GitHub 直接拒绝推送；建议单张控制在 5 MB 内。
  现在库里最大的一张约 6.9 MB，首屏加载会偏慢。
- 仓库建议保持在 1 GB 以内，GitHub Pages 站点也有 1 GB 软上限。
- 图片是公开的，别放私人照片或涉及隐私、版权问题的素材。
- **本机 git 走代理**：这台机器上 git 已配置
  `http.proxy = http://127.0.0.1:7897`（只配在本仓库）。
  代理软件必须开着，否则 `git push` 会报 `Connection was reset`。
  想撤销：`git config --unset http.proxy`。
- **改动 `tools\generate-manifest.ps1` 后请务必存成「UTF-8 带 BOM」。**
  本机只有 Windows PowerShell 5.1，它会把无 BOM 的 UTF-8 脚本当 ANSI 读，
  导致里面的中文变成乱码、脚本直接报语法错误。用 VS Code 的话在右下角
  编码处选 `UTF-8 with BOM` 保存。

---

## 工作原理

- `images.json` 是三级嵌套清单：`groups → collections → roles → images`。
- `script.js` 把 URL hash 解析成 `大类 / 图集 / 角色` 三段，据此切换视图；
  改 hash 会触发 `hashchange`，所以浏览器前进后退天然可用。
- 路由里的非法层级会自动回退到上一层（比如手工输入了不存在的角色名）。
- 第 1 级只有一个大类时，首页直接进入它，省掉一次没有意义的点击。
- 图片用 `loading="lazy"` 懒加载；图集封面优先用 `cover.*` 文件。
- 深色模式存 `localStorage`，首次访问跟随系统 `prefers-color-scheme`。
- 灯箱支持 `Esc` 关闭、`←` `→` 在**当前筛选结果**里翻页、点遮罩关闭。
- `.nojekyll` 让 GitHub Pages 跳过 Jekyll 处理，避免下划线开头的文件被忽略。
