/* =========================================================
   My Image Library — 图片库前端脚本
   ---------------------------------------------------------
   数据来源：同目录下的 images.json（由 tools/generate-manifest.ps1 生成）
   清单格式（数组，每个元素一张图）：
     {
       "file": "images/大图集1/角色1/001.jpg",  // 必填，相对本页面的路径
       "title": "图片标题",                     // 可选，默认用文件名
       "category": "大图集1",                   // 可选，一级分类（大图集），第一行按钮
       "subcategory": "角色1",                  // 可选，二级分类（角色），第二行筛选
       "description": "描述文字",               // 可选
       "tags": ["标签1", "标签2"]               // 可选，参与搜索
     }

   两级分类的交互：
     · 第一行永远显示「全部 + 各个大图集」
     · 选中某个大图集后，第二行出现该大图集下的小类别
     · 选中「全部」时隐藏第二行
   ========================================================= */

(function () {
    'use strict';

    /* ---------------- 配置 ---------------- */

    var PAGE_SIZE = 12;                 // 每页显示张数（4 列 × 3 行）
    var MANIFEST_URL = 'images.json';   // 图片清单地址
    var DEFAULT_CATEGORY = '未分类';
    var NO_SUBCATEGORY = '未分类';      // 图片直接放在大图集根目录时的二级分类名
    var ALL_CATEGORY = '全部';
    var STORAGE_KEY = 'image-library-dark';

    /* ---------------- DOM ---------------- */

    var el = {
        gallery: document.getElementById('gallery'),
        categorySection: document.getElementById('categorySection'),
        subcategorySection: document.getElementById('subcategorySection'),
        searchInput: document.getElementById('searchInput'),
        resultCount: document.getElementById('resultCount'),
        emptyMessage: document.getElementById('emptyMessage'),
        emptyTitle: document.getElementById('emptyTitle'),
        emptyText: document.getElementById('emptyText'),
        pagination: document.getElementById('pagination'),
        prevBtn: document.getElementById('prevBtn'),
        nextBtn: document.getElementById('nextBtn'),
        pageInfo: document.getElementById('pageInfo'),
        darkModeBtn: document.getElementById('darkModeBtn'),
        modal: document.getElementById('imageModal'),
        modalImage: document.getElementById('modalImage'),
        modalTitle: document.getElementById('modalTitle'),
        modalDescription: document.getElementById('modalDescription'),
        closeModal: document.getElementById('closeModal'),
        copyUrlBtn: document.getElementById('copyUrlBtn'),
        downloadBtn: document.getElementById('downloadBtn')
    };

    /* ---------------- 状态 ---------------- */

    var state = {
        images: [],            // 全部图片
        filtered: [],          // 当前筛选结果
        category: ALL_CATEGORY,      // 一级：大图集
        subcategory: ALL_CATEGORY,   // 二级：角色 / 小类别
        query: '',
        page: 1,
        modalIndex: -1         // 灯箱当前图片在 filtered 中的下标
    };

    /* ---------------- 工具 ---------------- */

    function baseName(path) {
        var name = String(path).split('/').pop();
        return name.replace(/\.[^.]+$/, '');
    }

    function toTagArray(tags) {
        if (Array.isArray(tags)) {
            return tags.map(function (t) { return String(t).trim(); }).filter(Boolean);
        }
        if (typeof tags === 'string') {
            return tags.split(/[,，;；]/).map(function (t) { return t.trim(); }).filter(Boolean);
        }
        return [];
    }

    // 把清单里的任意写法统一成内部结构
    function normalize(raw) {
        if (typeof raw === 'string') {
            raw = { file: raw };
        }
        if (!raw || typeof raw !== 'object') {
            return null;
        }

        var file = raw.file || raw.src || raw.url || raw.path;
        if (!file) {
            return null;
        }

        var category = raw.category || raw.folder || raw.album || DEFAULT_CATEGORY;
        var subcategory = raw.subcategory || raw.sub || raw.group || '';

        return {
            src: String(file),
            title: String(raw.title || raw.name || baseName(file)),
            description: String(raw.description || raw.desc || ''),
            category: String(category),
            subcategory: String(subcategory),
            tags: toTagArray(raw.tags)
        };
    }

    function parseManifest(data) {
        var list = Array.isArray(data) ? data : (data && Array.isArray(data.images) ? data.images : []);
        return list.map(normalize).filter(Boolean);
    }

    function debounce(fn, wait) {
        var timer = null;
        return function () {
            var args = arguments;
            clearTimeout(timer);
            timer = setTimeout(function () { fn.apply(null, args); }, wait);
        };
    }

    /* ---------------- 深色模式 ---------------- */

    function applyDarkMode(isDark) {
        document.body.classList.toggle('dark', isDark);
        if (el.darkModeBtn) {
            el.darkModeBtn.textContent = isDark ? '☀️' : '🌙';
            el.darkModeBtn.title = isDark ? '切换浅色模式' : '切换深色模式';
        }
    }

    function initDarkMode() {
        var saved = null;
        try {
            saved = localStorage.getItem(STORAGE_KEY);
        } catch (e) { /* 隐私模式下忽略 */ }

        var prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        applyDarkMode(saved === null ? prefersDark : saved === '1');

        if (el.darkModeBtn) {
            el.darkModeBtn.addEventListener('click', function () {
                var isDark = !document.body.classList.contains('dark');
                applyDarkMode(isDark);
                try {
                    localStorage.setItem(STORAGE_KEY, isDark ? '1' : '0');
                } catch (e) { /* 忽略 */ }
            });
        }
    }

    /* ---------------- 分类按钮（两级） ---------------- */

    // 按出现数量排序：图片多的排前面，同数量按中文拼音
    function sortByCount(counts) {
        return Object.keys(counts).sort(function (a, b) {
            if (counts[b] !== counts[a]) {
                return counts[b] - counts[a];
            }
            return a.localeCompare(b, 'zh');
        });
    }

    function renderChips(container, items, activeName, onPick) {
        container.innerHTML = '';
        items.forEach(function (item) {
            var btn = document.createElement('button');
            btn.className = 'category-btn' + (item.name === activeName ? ' active' : '');
            btn.dataset.category = item.name;
            btn.textContent = item.name + ' (' + item.count + ')';
            btn.addEventListener('click', function () { onPick(item.name); });
            container.appendChild(btn);
        });
    }

    // 一级：全部 + 各个大图集
    function buildCategories() {
        if (!el.categorySection) {
            return;
        }

        var counts = {};
        state.images.forEach(function (img) {
            counts[img.category] = (counts[img.category] || 0) + 1;
        });

        if (state.images.length === 0) {
            el.categorySection.innerHTML = '';
            buildSubcategories();
            return;
        }

        var items = [{ name: ALL_CATEGORY, count: state.images.length }];
        sortByCount(counts).forEach(function (name) {
            items.push({ name: name, count: counts[name] });
        });

        renderChips(el.categorySection, items, state.category, function (name) {
            state.category = name;
            state.subcategory = ALL_CATEGORY;   // 换大图集时重置二级筛选
            state.page = 1;
            buildCategories();                  // 重新渲染两级高亮
            render();
        });

        buildSubcategories();
    }

    // 二级：只在选中具体大图集时显示该大图集下的小类别
    function buildSubcategories() {
        if (!el.subcategorySection) {
            return;
        }

        function hide() {
            el.subcategorySection.style.display = 'none';
            el.subcategorySection.innerHTML = '';
            state.subcategory = ALL_CATEGORY;
        }

        if (state.category === ALL_CATEGORY) {
            hide();
            return;
        }

        var counts = {};
        state.images.forEach(function (img) {
            if (img.category !== state.category) {
                return;
            }
            var key = img.subcategory || NO_SUBCATEGORY;
            counts[key] = (counts[key] || 0) + 1;
        });

        var names = sortByCount(counts);

        // 该大图集只有一种小类别（或没有子文件夹）时，这一行没有意义
        if (names.length < 2) {
            hide();
            return;
        }

        var total = 0;
        names.forEach(function (n) { total += counts[n]; });

        var items = [{ name: ALL_CATEGORY, count: total }];
        names.forEach(function (name) {
            items.push({ name: name, count: counts[name] });
        });

        renderChips(el.subcategorySection, items, state.subcategory, function (name) {
            state.subcategory = name;
            state.page = 1;
            buildSubcategories();
            render();
        });

        el.subcategorySection.style.display = '';
    }

    /* ---------------- 筛选 ---------------- */

    function applyFilter() {
        var q = state.query.trim().toLowerCase();

        state.filtered = state.images.filter(function (img) {
            if (state.category !== ALL_CATEGORY && img.category !== state.category) {
                return false;
            }
            if (state.subcategory !== ALL_CATEGORY) {
                var sub = img.subcategory || NO_SUBCATEGORY;
                if (sub !== state.subcategory) {
                    return false;
                }
            }
            if (!q) {
                return true;
            }
            var haystack = [img.title, img.category, img.subcategory, img.description, img.src]
                .concat(img.tags)
                .join(' ')
                .toLowerCase();
            return haystack.indexOf(q) !== -1;
        });

        var maxPage = Math.max(1, Math.ceil(state.filtered.length / PAGE_SIZE));
        if (state.page > maxPage) {
            state.page = maxPage;
        }
    }

    /* ---------------- 渲染 ---------------- */

    function createCard(img, index) {
        var card = document.createElement('article');
        card.className = 'image-card';
        card.tabIndex = 0;
        card.setAttribute('role', 'button');
        card.setAttribute('aria-label', '查看 ' + img.title);

        var wrapper = document.createElement('div');
        wrapper.className = 'image-wrapper';

        var image = document.createElement('img');
        image.src = img.src;
        image.alt = img.title;
        image.loading = 'lazy';
        image.decoding = 'async';
        image.addEventListener('error', function () {
            wrapper.innerHTML = '';
            var fail = document.createElement('div');
            fail.className = 'loading';
            fail.textContent = '图片加载失败';
            wrapper.appendChild(fail);
        });
        wrapper.appendChild(image);

        var info = document.createElement('div');
        info.className = 'image-info';

        var title = document.createElement('h3');
        title.className = 'image-title';
        title.textContent = img.title;
        title.title = img.title;

        var category = document.createElement('div');
        category.className = 'image-category';
        category.textContent = img.subcategory
            ? img.category + ' / ' + img.subcategory
            : img.category;

        info.appendChild(title);
        info.appendChild(category);

        if (img.tags.length) {
            var tagBox = document.createElement('div');
            tagBox.className = 'image-tags';
            img.tags.forEach(function (tag) {
                var chip = document.createElement('span');
                chip.className = 'image-tag';
                chip.textContent = tag;
                tagBox.appendChild(chip);
            });
            info.appendChild(tagBox);
        }

        card.appendChild(wrapper);
        card.appendChild(info);

        function open() { openModal(index); }
        card.addEventListener('click', open);
        card.addEventListener('keydown', function (e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                open();
            }
        });

        return card;
    }

    function render() {
        applyFilter();

        // --- 图片网格 ---
        el.gallery.innerHTML = '';
        var start = (state.page - 1) * PAGE_SIZE;
        var pageItems = state.filtered.slice(start, start + PAGE_SIZE);

        pageItems.forEach(function (img, i) {
            el.gallery.appendChild(createCard(img, start + i));
        });

        // --- 数量提示 ---
        if (state.images.length === 0) {
            el.resultCount.textContent = '图库中还没有图片';
            el.resultCount.classList.remove('error');
        } else if (state.filtered.length === state.images.length) {
            el.resultCount.textContent = '共 ' + state.images.length + ' 张图片';
            el.resultCount.classList.remove('error');
        } else {
            el.resultCount.textContent =
                '找到 ' + state.filtered.length + ' 张图片（共 ' + state.images.length + ' 张）';
            el.resultCount.classList.remove('error');
        }

        // --- 空状态 ---
        var isEmpty = pageItems.length === 0;
        el.emptyMessage.style.display = isEmpty ? 'block' : 'none';
        if (isEmpty) {
            if (state.images.length === 0) {
                el.emptyMessage.querySelector('.empty-icon').textContent = '🖼️';
                el.emptyTitle.textContent = '图库还是空的';
                el.emptyText.innerHTML =
                    '按 <code>images/大图集/角色/</code> 的层级放图片，' +
                    '然后双击 <code>tools\\update-gallery.cmd</code> 生成清单即可。';
            } else {
                el.emptyMessage.querySelector('.empty-icon').textContent = '🔍';
                el.emptyTitle.textContent = '没有找到图片';
                el.emptyText.textContent = '尝试搜索其他关键词';
            }
        }

        // --- 分页 ---
        var totalPages = Math.max(1, Math.ceil(state.filtered.length / PAGE_SIZE));
        var showPager = state.filtered.length > PAGE_SIZE;
        el.pagination.style.display = showPager ? 'flex' : 'none';
        el.pageInfo.textContent = '第 ' + state.page + ' / ' + totalPages + ' 页';
        el.prevBtn.disabled = state.page <= 1;
        el.nextBtn.disabled = state.page >= totalPages;
    }

    /* ---------------- 灯箱 ---------------- */

    function openModal(index) {
        var img = state.filtered[index];
        if (!img) {
            return;
        }

        state.modalIndex = index;
        el.modalImage.src = img.src;
        el.modalImage.alt = img.title;
        el.modalTitle.textContent = img.title;

        var parts = [];
        if (img.description) {
            parts.push(img.description);
        }
        parts.push('分类：' + img.category);
        if (img.subcategory) {
            parts.push('角色/小类：' + img.subcategory);
        }
        if (img.tags.length) {
            parts.push('标签：' + img.tags.join('、'));
        }
        el.modalDescription.textContent = parts.join(' · ');

        el.downloadBtn.href = img.src;
        el.downloadBtn.setAttribute('download', baseName(img.src));
        el.copyUrlBtn.textContent = '🔗 复制图片 URL';

        el.modal.classList.add('show');
        document.body.style.overflow = 'hidden';
    }

    function closeModal() {
        el.modal.classList.remove('show');
        document.body.style.overflow = '';
        el.modalImage.src = '';
        state.modalIndex = -1;
    }

    function stepModal(delta) {
        if (state.modalIndex < 0) {
            return;
        }
        var next = state.modalIndex + delta;
        if (next < 0 || next >= state.filtered.length) {
            return;
        }
        openModal(next);
    }

    function initModal() {
        el.closeModal.addEventListener('click', closeModal);

        // 点击遮罩关闭
        el.modal.addEventListener('click', function (e) {
            if (e.target === el.modal) {
                closeModal();
            }
        });

        document.addEventListener('keydown', function (e) {
            if (!el.modal.classList.contains('show')) {
                return;
            }
            if (e.key === 'Escape') {
                closeModal();
            } else if (e.key === 'ArrowLeft') {
                stepModal(-1);
            } else if (e.key === 'ArrowRight') {
                stepModal(1);
            }
        });

        el.copyUrlBtn.addEventListener('click', function () {
            var img = state.filtered[state.modalIndex];
            if (!img) {
                return;
            }
            var url = new URL(img.src, window.location.href).href;

            function done() {
                el.copyUrlBtn.textContent = '✅ 已复制';
                setTimeout(function () {
                    el.copyUrlBtn.textContent = '🔗 复制图片 URL';
                }, 1500);
            }

            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(url).then(done, function () { fallbackCopy(url, done); });
            } else {
                fallbackCopy(url, done);
            }
        });
    }

    function fallbackCopy(text, done) {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        try {
            document.execCommand('copy');
            done();
        } catch (e) {
            window.prompt('复制下面的链接：', text);
        }
        document.body.removeChild(ta);
    }

    /* ---------------- 事件绑定 ---------------- */

    function initControls() {
        if (el.searchInput) {
            el.searchInput.addEventListener('input', debounce(function (e) {
                state.query = e.target.value;
                state.page = 1;
                render();
            }, 150));
        }

        el.prevBtn.addEventListener('click', function () {
            if (state.page > 1) {
                state.page--;
                render();
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        });

        el.nextBtn.addEventListener('click', function () {
            var totalPages = Math.max(1, Math.ceil(state.filtered.length / PAGE_SIZE));
            if (state.page < totalPages) {
                state.page++;
                render();
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        });
    }

    /* ---------------- 启动 ---------------- */

    function showLoadError(message) {
        el.gallery.innerHTML = '';
        el.emptyMessage.style.display = 'block';
        el.emptyMessage.querySelector('.empty-icon').textContent = '⚠️';
        el.emptyTitle.textContent = '图片清单加载失败';
        el.emptyText.textContent = message;
        el.resultCount.textContent = '加载失败';
        el.resultCount.classList.add('error');
        el.pagination.style.display = 'none';
        if (el.subcategorySection) {
            el.subcategorySection.style.display = 'none';
        }
    }

    function init() {
        initDarkMode();
        initControls();
        initModal();

        fetch(MANIFEST_URL, { cache: 'no-cache' })
            .then(function (res) {
                if (!res.ok) {
                    throw new Error('HTTP ' + res.status);
                }
                return res.json();
            })
            .then(function (data) {
                state.images = parseManifest(data);
                buildCategories();
                render();
            })
            .catch(function (err) {
                console.error('[Image Library] 无法加载 ' + MANIFEST_URL, err);
                showLoadError(
                    '无法读取 ' + MANIFEST_URL + '（' + err.message + '）。' +
                    '如果你是在本地直接双击打开 index.html，浏览器会拦截读取，' +
                    '请改用本地预览：双击 tools\\preview.cmd（或在仓库目录运行 ' +
                    'node tools/preview.mjs）。'
                );
            });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
