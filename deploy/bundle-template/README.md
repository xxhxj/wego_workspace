# wego 生产运行包

这个目录是**已经打包好的运行产物**，不包含源码构建工具链，也不需要服务器安装 Vite/TypeScript。
前端在 Windows 本地构建，服务器只负责静态托管、Node API 和 Nginx。

```text
.
├── frontend/
│   ├── sso/       # 已构建的静态文件
│   ├── mockup/
│   ├── cad/
│   └── quiz/
├── backend/
│   ├── sso/       # Node 源码 + package.json + .env
│   ├── mockup/
│   └── quiz/
├── config/
│   └── deploy.env # 域名、数据库、MinIO、Quiz 密钥（含密钥，注意保护）
├── nginx/
│   ├── wego.conf          # 可直接复制到 /etc/nginx/conf.d/ 的单文件配置
│   └── wego.conf.template # 源模板，install-nginx.sh 用它重新渲染
├── logs/
├── centos-start.sh        # CentOS 一键：装后端依赖 + 后台启动 + 健康检查
├── install-backends.sh
├── seed-backends.sh
├── start-backends.sh
├── stop-backends.sh
├── update-app-urls.sh
├── install-nginx.sh
└── ecosystem.config.cjs
```

## 服务器要求

- CentOS 7+（或其他 Linux）
- Node.js 20+（建议 22 LTS）
- Nginx
- 可选：pm2（推荐）、certbot（HTTPS）
- MySQL 8 和 MinIO 可被服务器访问
- 数据库和 MinIO 保持远程；这台 1.8GB 内存服务器不要同时跑数据库

## 首次部署

把压缩包上传到服务器并解压到打包时填写的服务器目录（默认 `/opt/wego`）：

```bash
mkdir -p /opt/wego
tar -xzf wego-bundle.tar.gz -C /opt/wego
cd /opt/wego
chmod +x ./*.sh
```

一键启动后端（会自动安装缺失的生产依赖，然后后台启动三个 Node 服务）：

```bash
./centos-start.sh
```

它会同时把 `frontend/` 权限改成 Nginx 可读（Windows/SFTP 上传常见 600 导致 500）。手工替换前端后也可以执行：

```bash
chmod -R u+rwX,go+rX frontend
```

首次空库初始化（会写入演示账号，执行前确认/备份）：

```bash
./seed-backends.sh
```

安装 Nginx：

```bash
./install-nginx.sh
```

## Nginx（单文件）

`nginx/wego.conf` 是已经渲染好的完整配置，包含 SSO、包装样机、三维建模、答题闯关、MinIO 图片五个 `server` 块。

- 用脚本安装（推荐）：需要 root 或 sudo 运行 `./install-nginx.sh`，会按 bundle 的实际绝对路径重新渲染，安装到 `/etc/nginx/conf.d/wego.conf`，并清理旧的拆分配置文件。
- 手工安装：把 `nginx/wego.conf` 复制到 `/etc/nginx/conf.d/wego.conf`，然后：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

手工复制时要注意：`root` 是打包时填写的服务器目录（默认 `/opt/wego`），如果实际解压位置不同，用 `SERVER_ROOT=/实际目录 ./install-nginx.sh` 重新生成，或直接编辑文件里的路径。

CentOS 如果开启 SELinux 且访问页面返回 403：

```bash
sudo chcon -Rt httpd_sys_content_t /opt/wego/frontend
```

## 修改配置

`config/deploy.env` 包含：

- 域名：`BASE_DOMAIN` / `SSO_DOMAIN` / `MOCKUP_DOMAIN` / `CAD_DOMAIN` / `QUIZ_DOMAIN` / `FILES_DOMAIN`
- MySQL / MinIO 地址与账号
- `QUIZ_TOKEN_SECRET`
- `ENABLE_TLS`

**前端构建时的域名已经写进静态文件**。如果构建后修改域名，需要回到本地重新执行 `build-bundle.bat`（或 `build-bundle.sh`），不能只改服务器配置。

## HTTPS

先把 DNS 解析到服务器，修改 `config/deploy.env`：

```env
ENABLE_TLS=1
LETSENCRYPT_EMAIL=你的邮箱
```

然后重新执行：

```bash
./install-nginx.sh
```

注意：前端静态文件在构建时已经按 `http` 或 `https` 写入了 SSO 地址；如果要在 HTTPS 下正常跳转，建议本地打包前就把 `ENABLE_TLS=1`。重新执行 `install-nginx.sh` 会覆盖 certbot 对配置的修改，需要再次申请证书。

## 停止 / 日志

```bash
./stop-backends.sh
pm2 logs            # 使用 pm2 时
tail -f logs/*.log  # 未安装 pm2、使用 nohup 时
```

## 安全

- `config/deploy.env` 和 `backend/*/.env` 含数据库密码、MinIO 密钥、Quiz 密钥，不要提交 Git。
- 生产 MySQL 建议使用专用用户，不要用 root。
- 不要删除 `backend/sso/keys/`；删除后所有已签发 token 失效。
- 如果使用 HTTPS，浏览器访问图片的 `MINIO_PUBLIC_BASE` 必须是 HTTPS，或使用 `MINIO_PROXY=1` 由 Nginx 的 files 子域反代 MinIO。
