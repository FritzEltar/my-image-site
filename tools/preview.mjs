// 本地预览服务器：双击 tools\preview.cmd 即可
// 直接双击 index.html 是不行的 —— 浏览器会阻止 file:// 页面 fetch images.json
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exec } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
let PORT = Number(process.env.PORT || 8000);

const TYPES = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.txt': 'text/plain; charset=utf-8',
    '.md': 'text/plain; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.avif': 'image/avif',
    '.gif': 'image/gif',
    '.bmp': 'image/bmp',
    '.svg': 'image/svg+xml'
};

const server = http.createServer((req, res) => {
    let urlPath = decodeURIComponent(req.url.split('?')[0]);
    if (urlPath === '/') urlPath = '/index.html';

    const filePath = path.join(ROOT, urlPath);

    // 防止跳出仓库目录（注意要比较 ROOT + 分隔符，
    // 否则 my-image-site-evil 这类同前缀目录会绕过检查）
    if (filePath !== ROOT && !filePath.startsWith(ROOT + path.sep)) {
        res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
        return res.end('403 Forbidden');
    }

    fs.readFile(filePath, (err, data) => {
        if (err) {
            res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
            return res.end('404 Not Found: ' + urlPath);
        }
        res.writeHead(200, {
            'Content-Type': TYPES[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
            'Cache-Control': 'no-store'
        });
        res.end(data);
    });
});

function openBrowser(url) {
    const cmd = process.platform === 'win32' ? `start "" "${url}"`
        : process.platform === 'darwin' ? `open "${url}"`
            : `xdg-open "${url}"`;
    exec(cmd, () => { /* 打不开就算了，手动访问即可 */ });
}

server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
        PORT += 1;
        console.log(`端口 ${PORT - 1} 被占用，改用 ${PORT} ...`);
        server.listen(PORT, '127.0.0.1');
    } else {
        console.error(err);
        process.exit(1);
    }
});

server.listen(PORT, '127.0.0.1', () => {
    const url = `http://127.0.0.1:${PORT}/`;
    console.log('');
    console.log('  图片库本地预览已启动');
    console.log('  ' + url);
    console.log('');
    console.log('  目录：' + ROOT);
    console.log('  按 Ctrl+C 停止');
    console.log('');

    // 设置 NO_OPEN=1 可只起服务、不自动打开浏览器
    if (!process.env.NO_OPEN) {
        openBrowser(url);
    }
});
