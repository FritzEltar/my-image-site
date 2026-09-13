/* =========================================================
   My Image Library — 图库前端脚本
   ---------------------------------------------------------
   数据来源：同目录下的 images.json（由 tools/generate-manifest.ps1 生成）

   清单是三级嵌套结构：
     {
       "version": 2,
       "groups": [                       // 第 1 级：大类（如「全部」）
         {
           "name": "全部",
           "cover": "images/...",
           "collectionCount": 2,
           "imageCount": 11,
           "collections": [              // 第 2 级：大图集
             {
               "name": "大图集1",
               "path": "全部/大图集1",
               "cover": "images/...",    // 封面，每个图集固定一张
               "imageCount": 6,
               "roles": [                // 第 3 级：角色（没有「全部」这一档）
                 {
                   "name": "角色1",
                   "imageCount": 3,
                   "images": [ { "file": "...", "title": "...", "tags": [] } ]
                 }
               ]
             }
           ]
         }
       ]
     }

   导航（单页，不刷新、不开新网页）：
     #/                        只有一个大类时直接进它，否则显示大类列表
     #/全部                    该大类下的图集封面列表
     #/全部/大图集1            图集内部：角色页签 + 图片
     #/全部/大图集1/角色1      同上，并选中该角色
   浏览器前进 / 后退键可以直接用。
   ========================================================= */

(function () {
    'use strict';

    /* ---------------- 配置 ---------------- */

    var PAGE_SIZE = 12;                 // 每页显示张数（4 列 × 3 行）
    var MANIFEST_URL = 'images.json';   // 图片清单地址
    var STORAGE_KEY = 'image-library-dark';

    /* ---------------- DOM ---------------- */

    var el = {
        homeLink: document.getElementById('homeLink'),
        breadcrumb: document.getElementById('breadcrumb'),

        groupsView: document.getElementById('groupsView'),
        groupsGrid: document.getElementById('groupsGrid'),

        collectionsView: document.getElementById('collectionsView'),
        collectionsGrid: document.getElementById('collectionsGrid'),

        imagesView: document.getElementById('imagesView'),
        roleSection: document.getElementById('roleSection'),
        searchInput: document.getElementById('searchInput'),
        resultCount: document.getElementById('resultCount'),
        gallery: document.getElementById('gallery'),
        imagesEmpty: document.getElementById('imagesEmpty'),
        imagesEmptyTitle: document.getElementById('imagesEmptyTitle'),
        imagesEmptyText: document.getElementById('imagesEmptyText'),
        pagination: document.getElementById('pagination'),
        prevBtn: document.getElementById('prevBtn'),
        nextBtn: document.getElementById('nextBtn'),
        pageInfo: document.getElementById('pageInfo'),

        statusMessage: document.getElementById('statusMessage'),
        statusIcon: document.getElementById('statusIcon'),
        statusTitle: document.getElementById('statusTitle'),
        statusText: document.getElementById('statusText'),

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

    var data = { groups: [] };          // 完整清单

    var view = {
        group: null,        // 当前大类名
        collection: null,   // 当前大图集名
        role: null,         // 当前角色名
        query: '',          // 搜索词（只在图集内部生效）
        page: 1
    };

    var shownImages = [];               // 当前筛选出的全部图片（灯箱在其中前后翻）
    var modalIndex = -1;

    /* ---------------- 工具 ---------------- */

    function baseName(path) {
        var name = String(path).split('/').pop();
        return name.replace(/\.[^.]+$/, '');
    }

    function debounce(fn, wait) {
        var timer = null;
        return function () {
            var args = arguments;
            clearTimeout(timer);
            timer = setTimeout(function () { fn.apply(null, args); }, wait);
        };
    }

    /* ---------------- 路由 ---------------- */

    function parseHash() {
        var raw = location.hash.replace(/^#\/?/, '');
        if (!raw) {
            return { group: null, collection: null, role: null };
        }
        // 先按 / 切分再解码，这样角色名里的 / 会以 %2F 形式保留在单个片段内
        var parts = raw.split('/').filter(function (p) { return p !== ''; });
        return {
            group: parts[0] ? decodeURIComponent(parts[0]) : null,
            collection: parts[1] ? decodeURIComponent(parts[1]) : null,
            role: parts[2] ? decodeURIComponent(parts[2]) : null
        };
    }

    function buildHash(group, collection, role) {
        var parts = [group, collection, role]
            .filter(function (p) { return p; })
            .map(encodeURIComponent);
        return '#/' + parts.join('/');
    }

    function navigate(group, collection, role) {
        var hash = buildHash(group, collection, role);
        if (location.hash === hash) {
            applyRoute();
        } else {
            location.hash = hash;   // 触发 hashchange -> applyRoute
        }
    }

    /* ---------------- 数据查找 ---------------- */

    function findGroup(name) {
        for (var i = 0; i < data.groups.length; i++) {
            if (data.groups[i].name === name) { return data.groups[i]; }
        }
        return null;
    }

    function findCollection(group, name) {
        if (!group) { return null; }
        for (var i = 0; i < group.collections.length; i++) {
            if (group.collections[i].name === name) { return group.collections[i]; }
        }
        return null;
    }

    function findRole(collection, name) {
        if (!collection) { return null; }
        for (var i = 0; i < collection.roles.length; i++) {
            if (collection.roles[i].name === name) { return collection.roles[i]; }
        }
        return null;
    }

    // 把路由解析成合法状态：找不到的层级一律回退到上一层
    function applyRoute() {
        var route = parseHash();

        var group = findGroup(route.group);
        if (!group && data.groups.length === 1 && !route.group) {
            group = data.groups[0];              // 只有一个大类时自动进入
        }
        if (!group) {
            view.group = null;
            view.collection = null;
            view.role = null;
            view.query = '';
            view.page = 1;
            render();
            return;
        }

        var collection = findCollection(group, route.collection);
        var role = findRole(collection, route.role);

        view.group = group.name;
        view.collection = collection ? collection.name : null;
        view.role = role ? role.name : null;
        view.query = '';
        view.page = 1;
        if (el.searchInput) { el.searchInput.value = ''; }

        render();
    }

    /* ---------------- 视图切换 ---------------- */

    function show(el2, visible) {
        if (el2) { el2.style.display = visible ? '' : 'none'; }
    }

    function render() {
        show(el.groupsView, false);
        show(el.collectionsView, false);
        show(el.imagesView, false);
        show(el.statusMessage, false);

        var group = findGroup(view.group);

        if (!group) {
            // 多个大类时显示大类列表；图库为空则由 renderStatus 接管
            if (data.groups.length > 1) {
                renderGroups();
                show(el.groupsView, true);
            }
            renderBreadcrumb();
            return;
        }

        if (!view.collection) {
            renderCollections(group);
            show(el.collectionsView, true);
            renderBreadcrumb();
            return;
        }

        renderImages(group);
        show(el.imagesView, true);
        renderBreadcrumb();
    }

    function renderBreadcrumb() {
        el.breadcrumb.innerHTML = '';

        function crumb(text, onClick, isCurrent) {
            var node;
            if (onClick) {
                node = document.createElement('button');
                node.className = 'crumb crumb-link';
                node.addEventListener('click', onClick);
            } else {
                node = document.createElement('span');
                node.className = 'crumb' + (isCurrent ? ' crumb-current' : '');
            }
            node.textContent = text;
            el.breadcrumb.appendChild(node);
        }

        function sep() {
            var s = document.createElement('span');
            s.className = 'crumb-sep';
            s.textContent = '/';
            el.breadcrumb.appendChild(s);
        }

        var parts = [];
        var multi = data.groups.length > 1;

        if (multi) {
            parts.push({
                text: '全部图库',
                onClick: view.group ? function () { navigate(null, null, null); } : null,
                current: !view.group
            });
        }

        if (view.group) {
            var groupName = view.group;
            parts.push({
                text: groupName,
                // 已进入某个图集时，点大类的名字返回该大类的图集列表
                onClick: view.collection ? function () {
                    navigate(groupName, null, null);
                } : null,
                current: !view.collection
            });
        }

        if (view.collection) {
            parts.push({ text: view.collection, onClick: null, current: true });
        }

        parts.forEach(function (part, i) {
            if (i > 0) { sep(); }
            crumb(part.text, part.onClick, part.current);
        });
    }

    /* ---------------- 视图 1：大类 ---------------- */

    function renderGroups() {
        el.groupsGrid.innerHTML = '';

        data.groups.forEach(function (group) {
            el.groupsGrid.appendChild(createCoverCard({
                title: group.name,
                subtitle: group.collectionCount + ' 个图集 · ' + group.imageCount + ' 张图',
                cover: group.coverThumb || group.cover,
                coverFallback: group.cover,
                alt: group.name,
                onClick: function () { navigate(group.name, null, null); }
            }));
        });
    }

    /* ---------------- 视图 2：图集封面 ---------------- */

    function renderCollections(group) {
        el.collectionsGrid.innerHTML = '';

        if (group.collections.length === 0) {
            return;
        }

        group.collections.forEach(function (collection) {
            var roleCount = collection.roles.filter(function (r) {
                return r.name !== '草稿箱';
            }).length;
            var bits = [collection.imageCount + ' 张图'];
            if (roleCount > 0) { bits.push(roleCount + ' 个角色'); }
            if (findRole(collection, '草稿箱')) { bits.push('含草稿箱'); }

            el.collectionsGrid.appendChild(createCoverCard({
                title: collection.name,
                subtitle: bits.join(' · '),
                // 封面卡是小图，优先用缩略图
                cover: collection.coverThumb || collection.cover,
                coverFallback: collection.cover,
                alt: collection.name,
                onClick: function () {
                    navigate(group.name, collection.name, null);
                }
            }));
        });
    }

    function createCoverCard(opts) {
        var card = document.createElement('article');
        card.className = 'cover-card';
        card.tabIndex = 0;
        card.setAttribute('role', 'button');
        card.setAttribute('aria-label', opts.title);

        var wrap = document.createElement('div');
        wrap.className = 'cover-image';

        var img = document.createElement('img');
        img.src = opts.cover;
        img.alt = opts.alt || opts.title;
        img.loading = 'lazy';
        img.decoding = 'async';

        // 注意用布尔标记而不是比较 URL：img.src 会被浏览器编码，中文路径比不出来
        var triedFallback = false;
        img.addEventListener('error', function () {
            if (!triedFallback && opts.coverFallback) {   // 缩略图缺失就退回原图
                triedFallback = true;
                img.src = opts.coverFallback;
                return;
            }
            wrap.innerHTML = '';
            var fail = document.createElement('div');
            fail.className = 'cover-fallback';
            fail.textContent = '无封面';
            wrap.appendChild(fail);
        });
        wrap.appendChild(img);

        var info = document.createElement('div');
        info.className = 'cover-info';

        var title = document.createElement('h3');
        title.className = 'cover-title';
        title.textContent = opts.title;

        var sub = document.createElement('p');
        sub.className = 'cover-subtitle';
        sub.textContent = opts.subtitle;

        info.appendChild(title);
        info.appendChild(sub);

        card.appendChild(wrap);
        card.appendChild(info);

        card.addEventListener('click', opts.onClick);
        card.addEventListener('keydown', function (e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                opts.onClick();
            }
        });

        return card;
    }

    /* ---------------- 视图 3：图集内部 ---------------- */

    // 搜索时跨全图集，否则只看当前角色
    function computeShownImages(collection) {
        var q = view.query.trim().toLowerCase();

        var pool = [];
        if (q) {
            collection.roles.forEach(function (role) {
                role.images.forEach(function (img) {
                    pool.push({ img: img, role: role.name });
                });
            });
        } else {
            var role = findRole(collection, view.role) || collection.roles[0];
            if (role) {
                role.images.forEach(function (img) {
                    pool.push({ img: img, role: role.name });
                });
            }
        }

        if (q) {
            pool = pool.filter(function (entry) {
                var img = entry.img;
                var haystack = [img.title, img.description, entry.role, img.file]
                    .concat(img.tags || [])
                    .join(' ')
                    .toLowerCase();
                return haystack.indexOf(q) !== -1;
            });
        }

        return pool;
    }

    function renderRoleTabs(collection, searching) {
        el.roleSection.innerHTML = '';

        if (collection.roles.length === 0) {
            return;
        }

        var label = document.createElement('span');
        label.className = 'role-label';
        label.textContent = searching ? '搜索中' : '角色';
        el.roleSection.appendChild(label);

        collection.roles.forEach(function (role) {
            var btn = document.createElement('button');
            btn.className = 'role-tab' + (!searching && role.name === view.role ? ' active' : '');
            btn.dataset.role = role.name;
            btn.textContent = role.name + ' (' + role.imageCount + ')';
            btn.addEventListener('click', function () {
                navigate(view.group, view.collection, role.name);
            });
            el.roleSection.appendChild(btn);
        });
    }

    function createCard(entry, index) {
        var img = entry.img;

        var card = document.createElement('article');
        card.className = 'image-card';
        card.tabIndex = 0;
        card.setAttribute('role', 'button');
        card.setAttribute('aria-label', '查看 ' + img.title);

        var wrapper = document.createElement('div');
        wrapper.className = 'image-wrapper';

        var image = document.createElement('img');
        // 网格里用小图（缩略图），点开灯箱才加载原图
        image.src = img.thumb || img.file;
        image.alt = img.title;
        image.loading = 'lazy';
        image.decoding = 'async';

        var usingThumb = !!(img.thumb && img.thumb !== img.file);
        image.addEventListener('error', function () {
            if (usingThumb) {          // 缩略图缺失就退回原图
                usingThumb = false;
                image.src = img.file;
                return;
            }
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

        var role = document.createElement('div');
        role.className = 'image-category';
        role.textContent = entry.role;

        info.appendChild(title);
        info.appendChild(role);

        var tags = img.tags || [];
        if (tags.length) {
            var tagBox = document.createElement('div');
            tagBox.className = 'image-tags';
            tags.forEach(function (tag) {
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

    function renderImages(group) {
        var collection = findCollection(group, view.collection);
        if (!collection) {
            navigate(group.name, null, null);
            return;
        }

        var searching = view.query.trim() !== '';

        // 没有指定角色时默认选第一个（角色列表里没有「全部」）
        if (!searching && !findRole(collection, view.role)) {
            view.role = collection.roles.length ? collection.roles[0].name : null;
        }

        renderRoleTabs(collection, searching);

        shownImages = computeShownImages(collection);

        // 分页
        var totalPages = Math.max(1, Math.ceil(shownImages.length / PAGE_SIZE));
        if (view.page > totalPages) { view.page = totalPages; }
        var start = (view.page - 1) * PAGE_SIZE;
        var pageItems = shownImages.slice(start, start + PAGE_SIZE);

        el.gallery.innerHTML = '';
        pageItems.forEach(function (entry, i) {
            el.gallery.appendChild(createCard(entry, start + i));
        });

        // 数量文案
        el.resultCount.textContent = searching
            ? '在本图集搜到 ' + shownImages.length + ' 张（共 ' + collection.imageCount + ' 张）'
            : collection.name + ' · ' + (view.role || '') + ' · ' + shownImages.length + ' 张';

        // 空状态
        var isEmpty = pageItems.length === 0;
        show(el.imagesEmpty, isEmpty);
        if (isEmpty) {
            el.imagesEmptyTitle.textContent = searching ? '没有找到图片' : '这个分类还没有图片';
            el.imagesEmptyText.textContent = searching
                ? '换个关键词试试'
                : '把图片放进对应的文件夹，重跑一次生成脚本即可。';
        }

        // 分页控件
        var showPager = shownImages.length > PAGE_SIZE;
        show(el.pagination, showPager);
        if (showPager) {
            el.pageInfo.textContent = '第 ' + view.page + ' / ' + totalPages + ' 页';
            el.prevBtn.disabled = view.page <= 1;
            el.nextBtn.disabled = view.page >= totalPages;
        }
    }

    /* ---------------- 全局状态 ---------------- */

    function renderStatus(icon, title, text) {
        el.statusIcon.textContent = icon;
        el.statusTitle.textContent = title;
        el.statusText.innerHTML = text;
        show(el.statusMessage, true);
        el.breadcrumb.innerHTML = '';
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
        try { saved = localStorage.getItem(STORAGE_KEY); } catch (e) { /* 忽略 */ }

        var prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        applyDarkMode(saved === null ? prefersDark : saved === '1');

        if (el.darkModeBtn) {
            el.darkModeBtn.addEventListener('click', function () {
                var isDark = !document.body.classList.contains('dark');
                applyDarkMode(isDark);
                try { localStorage.setItem(STORAGE_KEY, isDark ? '1' : '0'); } catch (e) { /* 忽略 */ }
            });
        }
    }

    /* ---------------- 灯箱 ---------------- */

    function openModal(index) {
        var entry = shownImages[index];
        if (!entry) { return; }

        var img = entry.img;
        modalIndex = index;

        el.modalImage.src = img.file;
        el.modalImage.alt = img.title;
        el.modalTitle.textContent = img.title;

        var parts = [];
        if (img.description) { parts.push(img.description); }
        parts.push('图集：' + view.collection);
        parts.push('角色：' + entry.role);
        if ((img.tags || []).length) { parts.push('标签：' + img.tags.join('、')); }
        el.modalDescription.textContent = parts.join(' · ');

        el.downloadBtn.href = img.file;
        el.downloadBtn.setAttribute('download', baseName(img.file));
        el.copyUrlBtn.textContent = '🔗 复制图片 URL';

        el.modal.classList.add('show');
        document.body.style.overflow = 'hidden';
    }

    function closeModal() {
        el.modal.classList.remove('show');
        document.body.style.overflow = '';
        el.modalImage.src = '';
        modalIndex = -1;
    }

    function stepModal(delta) {
        if (modalIndex < 0) { return; }
        var next = modalIndex + delta;
        if (next < 0 || next >= shownImages.length) { return; }
        openModal(next);
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

    function initModal() {
        el.closeModal.addEventListener('click', closeModal);

        el.modal.addEventListener('click', function (e) {
            if (e.target === el.modal) { closeModal(); }
        });

        document.addEventListener('keydown', function (e) {
            if (!el.modal.classList.contains('show')) { return; }
            if (e.key === 'Escape') { closeModal(); }
            else if (e.key === 'ArrowLeft') { stepModal(-1); }
            else if (e.key === 'ArrowRight') { stepModal(1); }
        });

        el.copyUrlBtn.addEventListener('click', function () {
            var entry = shownImages[modalIndex];
            if (!entry) { return; }
            var url = new URL(entry.img.file, window.location.href).href;

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

    /* ---------------- 控件 ---------------- */

    function initControls() {
        if (el.homeLink) {
            el.homeLink.addEventListener('click', function (e) {
                e.preventDefault();
                if (data.groups.length === 1) {
                    navigate(data.groups[0].name, null, null);
                } else {
                    navigate(null, null, null);
                }
            });
        }

        if (el.searchInput) {
            el.searchInput.addEventListener('input', debounce(function (e) {
                view.query = e.target.value;
                view.page = 1;
                renderImages(findGroup(view.group));
            }, 150));
        }

        el.prevBtn.addEventListener('click', function () {
            if (view.page > 1) {
                view.page--;
                renderImages(findGroup(view.group));
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        });

        el.nextBtn.addEventListener('click', function () {
            var totalPages = Math.max(1, Math.ceil(shownImages.length / PAGE_SIZE));
            if (view.page < totalPages) {
                view.page++;
                renderImages(findGroup(view.group));
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        });
    }

    /* ---------------- 启动 ---------------- */

    function init() {
        initDarkMode();
        initControls();
        initModal();

        window.addEventListener('hashchange', applyRoute);

        fetch(MANIFEST_URL, { cache: 'no-cache' })
            .then(function (res) {
                if (!res.ok) { throw new Error('HTTP ' + res.status); }
                return res.json();
            })
            .then(function (payload) {
                // 兼容空清单 [] 与 {version, groups}
                data.groups = Array.isArray(payload)
                    ? []
                    : (payload && Array.isArray(payload.groups) ? payload.groups : []);

                var total = data.groups.reduce(function (sum, g) { return sum + g.imageCount; }, 0);

                if (total === 0) {
                    renderStatus(
                        '🖼️',
                        '图库还是空的',
                        '按 <code>images/大类/图集/角色/</code> 的层级放图片，' +
                        '然后双击 <code>tools\\update-gallery.cmd</code> 生成清单。'
                    );
                    return;
                }

                applyRoute();
            })
            .catch(function (err) {
                console.error('[Image Library] 无法加载 ' + MANIFEST_URL, err);
                renderStatus(
                    '⚠️',
                    '图片清单加载失败',
                    '无法读取 ' + MANIFEST_URL + '（' + err.message + '）。' +
                    '如果是在本地直接双击打开 index.html，浏览器会拦截读取，' +
                    '请改用本地预览：双击 tools\\preview.cmd。'
                );
            });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
