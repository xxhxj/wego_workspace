# 生产部署

> 1.8GB 小内存服务器请不要在服务器上构建前端。在 Windows 本地双击 `build-bundle.bat` 生成运行包，服务器只解压运行，说明见 `bundle-template/README.md`。

## 本地一键打包（Windows）

先确认 `deploy.env` 里的域名、数据库、MinIO 配置正确，然后双击：

```text
deploy\build-bundle.bat
```

按提示输入两个路径：

- **输出目录**：打包结果放在哪里，留空为 `deploy\dist`。生成 `wego-bundle\` 和 `wego-bundle.tar.gz`。
- **服务器部署目录**：留空为 `/opt/wego`。它会被写进 Nginx 配置的 `root`。

也可以带参数运行：

```bat
build-bundle.bat D:\release /opt/wego
```

打包完成后，输出目录里的 `wego-bundle/` 包含：

- `nginx/wego.conf`：单文件 Nginx 配置（SSO / 样机 / 建模 / 闯关 / 图片五个 server）
- `centos-start.sh`：服务器上一键安装后端依赖 + 后台启动 + 健康检查
- `install-nginx.sh`：安装上面的单文件配置到 `/etc/nginx/conf.d/`
- 四个已构建的前端和三个后端源码

服务器上：

```bash
mkdir -p /opt/wego
tar -xzf wego-bundle.tar.gz -C /opt/wego
cd /opt/wego
./centos-start.sh
./install-nginx.sh
```

> 压缩包里含 `config/deploy.env` 和 `backend/*/.env`（数据库/MinIO/Quiz 密钥），只传到自己的服务器，不要提交 Git 或发到公共网盘。

Linux/macOS 下打包用：

```bash
cd deploy
./build-bundle.sh /tmp/release /opt/wego
```

## 服务器发版（release.sh）

把 `release.sh` 放到服务器的运行目录（只需放一次）：

```text
/opt/others/deployWego/wego/release.sh
```

以后每次发版：

1. 本地双击 `build-bundle.bat` 生成新包
2. 把 `wego-bundle.tar.gz` 上传到 `/opt/others/deployWego/wego/`
3. 执行发版脚本：

```bash
cd /opt/others/deployWego/wego
chmod +x release.sh
./release.sh
```

脚本会依次：校验压缩包结构 → 备份当前版本 → 整包覆盖解压 → 执行 `centos-start.sh` → 检查 pm2、三个接口、四个页面、分享页、图片域名和前端构建地址，最后输出通过/失败清单。

- 备份目录：`/opt/others/deployWego/wego-backups/`，默认保留最近 5 份
- 发版日志：`/var/log/wego-release.log`
- 检查失败时会打印回滚命令，不会自动回滚
- `release.sh` 不放进运行包，所以整包解压不会覆盖正在执行的脚本

这套脚本把四个系统部署为：

- 三个 Node 后端：`3001`（SSO）、`3000`（包装样机）、`3002`（答题闯关），由 pm2 托管
- 四个静态前端：由 Nginx 托管 `dist`
- 一个可选的 `files` 子域：反代 MinIO，给包装样机提供图片/分享预览

不使用 `start.sh` 的 Vite dev server。

## 服务器目录

```text
/opt/wego/
├── wego_sso/
├── wego_3d_texture/
├── wego_fingertip_3d_web/
├── wego_quiz_3d/
└── deploy/
```

四个仓库的目录名必须保持不变，并且和 `deploy/` 平级。

## 前置条件

- Linux + 可 sudo 的部署用户
- Node.js 20+（建议 22 LTS）、npm、pm2、Nginx
- 可访问的 MySQL 8
- 可访问的 MinIO（或可访问的对象存储/CDN）
- 域名 DNS 已解析到服务器；防火墙/安全组放行 80/443
- 如果要 HTTPS：`certbot` + `python3-certbot-nginx`

MySQL 和 MinIO 不会被脚本安装；脚本只使用 `deploy.env` 里的地址。

## 上传脚本并运行

在本地把 `deploy/` 传到服务器：

```bash
scp -r deploy user@your-server:/opt/wego/
```

服务器上：

```bash
ssh user@your-server
cd /opt/wego
git clone git@github.com:xxhxj/wego_sso.git
git clone git@github.com:xxhxj/wego_3d_texture.git
git clone git@github.com:xxhxj/wego_fingertip_3d_web.git
git clone git@github.com:xxhxj/wego_quiz_3d.git
nano deploy/deploy.env
chmod +x deploy/deploy.sh
# 先只检查配置、端口和依赖，不修改服务器
PREFLIGHT_ONLY=1 ./deploy/deploy.sh
# 确认无误后正式部署
./deploy/deploy.sh
```

`deploy.env` 是由本地实际 `.env` 生成的，已经带了本机的 MySQL/MinIO 配置，但**域名需要你改**：

```env
BASE_DOMAIN=你的域名.com
ENABLE_TLS=0          # DNS 和 80 端口就绪后可改 1
LETSENCRYPT_EMAIL=
RUN_SEED=0            # 空库首次部署改成 1
```

如果 MySQL/MinIO 在服务器本机，把 `MYSQL_HOST` / `MINIO_ENDPOINT` 改成 `127.0.0.1`；如果仍在远程，保持现有地址并确认服务器能访问。

## 首次部署

- **空数据库**：把 `RUN_SEED=1`，脚本会依次执行三个 seed。
  - seed 会写入演示账号（`admin/admin123`、`xiaoming/123456` 等），上线前请改密。
  - `wego_quiz_3d` 的 seed 可能会重置演示账号密码，已有数据时不要随意重跑。
- **已有数据**：保持 `RUN_SEED=0`，脚本只部署代码和配置。
- 部署前建议先备份 MySQL 数据库。

## HTTPS

1. 先把 DNS 解析到服务器，确认 80 端口可访问；
2. `deploy.env` 设置：
   ```env
   ENABLE_TLS=1
   LETSENCRYPT_EMAIL=你的邮箱
   ```
3. 重新执行 `./deploy/deploy.sh`，脚本会调用 certbot 申请证书并跳转 HTTPS。

## MinIO 图片

推荐保持：

```env
MINIO_PROXY=1
MINIO_PROXY_TARGET=http://127.0.0.1:9000
```

这样浏览器通过 `https://files.你的域名/wego-mockup/...` 访问图片，避免 HTTPS 页面加载 HTTP 图片。

如果你已有独立的 HTTPS MinIO/CDN：

```env
MINIO_PROXY=0
MINIO_PUBLIC_BASE=https://your-cdn.example.com/wego-mockup
```

## 验证

```bash
pm2 status
pm2 logs wego-sso-api --lines 50
curl http://127.0.0.1:3001/api/health
curl http://127.0.0.1:3000/api/health
curl http://127.0.0.1:3002/api/health
```

浏览器访问：

```text
https://sso.你的域名
https://mockup.你的域名
https://cad.你的域名
https://quiz.你的域名
```

SSO 登录后应该能跳到另外三个系统；`sys_app.entry_url` 会被脚本更新为正式地址。

## 安全提醒

- `deploy.env` 含数据库密码、MinIO 密钥、Quiz token 密钥，**不要提交 Git**；已在 `deploy/.gitignore` 排除。
- 生产 MySQL 建议创建专用用户，不要用 root；并限制来源 IP。
- `wego_sso/backend/keys` 要持久化/备份；删除会让所有 token 失效。
- 邮件、DNS、云安全组、数据库备份需在服务器/云平台侧配置，脚本不代做。
- 如果本地和生产共用同一个远程数据库，脚本更新 `sys_app.entry_url` 后，本地 SSO 的系统入口也会指向正式域名。
