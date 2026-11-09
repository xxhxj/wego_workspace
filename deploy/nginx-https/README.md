# wego HTTPS 部署（接入现有 nginx.conf）

当前服务器情况：

- Nginx 主配置是单文件，里面**没有** `include /etc/nginx/conf.d/*.conf;`
- 已有证书只有 `ktv.xzyang.cn`、`www.xzyang.cn`，不覆盖新子域
- wego 运行目录：`/opt/others/deployWego/wego`
- 后端已由 pm2 启动，监听 `3001 / 3000 / 3002`

本目录四个文件：

- `wego.conf.http-first`：首次签发证书用，只监听 80
- `wego.conf`：最终 HTTPS 配置，80 跳转 443 + 五个 443 站点
- `issue-https.sh`：一键签发并切换 HTTPS，同时安装续期钩子和定时任务
- `renew-https.sh`：定期续期并重载 Nginx

证书方案：五个子域签在**同一张 SAN 证书**里，目录为 `/etc/letsencrypt/live/sso.xzyang.cn/`。

## 快速用法（推荐）

把整个 `nginx-https` 目录上传到服务器，例如 `/opt/others/deployWego/nginx-https`，然后：

```bash
cd /opt/others/deployWego/nginx-https
chmod +x *.sh
./issue-https.sh 你的邮箱@example.com
```

脚本会依次完成：

1. 检查五个子域 DNS
2. 确认 `nginx.conf` 已 include 了 `conf.d`（没生效会直接报错）
3. 装 HTTP 配置 → 签发证书 → 装 HTTPS 配置 → reload
4. 安装续期钩子 `/etc/letsencrypt/renewal-hooks/deploy/reload-wego-nginx.sh`
5. 安装 `/etc/cron.d/wego-cert-renew`，每天 03:17 执行续期
6. 输出五个域名的 https 访问状态

日志：

```text
/var/log/wego-issue-https.log
/var/log/wego-cert-renew.log
```

路径或域名不一样时用环境变量覆盖，例如：

```bash
BASE_DOMAIN=xzyang.cn \
WEB_ROOT=/opt/others/deployWego/wego \
NGINX_BIN=/opt/others/sound_sea_party/front/nginx-1.28.2/sbin/nginx \
NGINX_CONF=/opt/others/sound_sea_party/front/nginx-1.28.2/conf/nginx.conf \
./issue-https.sh 你的邮箱@example.com
```

下面是从头手动操作的步骤（脚本内部做的事情），排错时参考。

---

## 1. DNS

五个子域都解析到这台服务器：

```text
sso.xzyang.cn
mockup.xzyang.cn
cad.xzyang.cn
quiz.xzyang.cn
files.xzyang.cn
```

验证（每行都要返回服务器 IP）：

```bash
for d in sso mockup cad quiz files; do echo -n "$d: "; getent hosts $d.xzyang.cn || echo "未解析"; done
```

服务器没装 `dig` 时不用安装；想用 `dig/nslookup` 可以 `yum install -y bind-utils`。

如果使用 CDN/代理，确认回源到本机 80/443。

## 2. Nginx 实际路径（已按当前服务器确认）

```bash
ps -ef | grep "nginx: master"
# root ... nginx: master process /opt/others/sound_sea_party/front/nginx-1.28.2/sbin/nginx
#   -c /opt/others/sound_sea_party/front/nginx-1.28.2/conf/nginx.conf

nginx -V 2>&1 | tr ' ' '\n' | grep -E "conf-path|prefix"
# --prefix=/www/server/nginx
```

注意：`--prefix=/www/server/nginx` 意味着 `include conf.d/*.conf;` 相对路径会去 `/www/server/nginx/conf.d/` 找，**不是**配置文件旁边的目录。这里统一用绝对路径。

后面的命令都用这两个变量，避免操作到 `/www/server/nginx` 那套 Nginx：

```bash
NGINX=/opt/others/sound_sea_party/front/nginx-1.28.2/sbin/nginx
CONF=/opt/others/sound_sea_party/front/nginx-1.28.2/conf/nginx.conf
$NGINX -t -c "$CONF"
$NGINX -s reload -c "$CONF"
```

## 3. 让主配置加载 conf.d

备份：

```bash
cp "$CONF" "$CONF.bak.$(date +%F_%H%M)"
```

在 `http { ... }` 里加一行**绝对路径**（注意是 `conf.d`，不是 `cond.d`）：

```nginx
include /opt/others/sound_sea_party/front/nginx-1.28.2/conf/conf.d/*.conf;
```

创建目录并检查：

```bash
CONF_DIR=/opt/others/sound_sea_party/front/nginx-1.28.2/conf/conf.d
mkdir -p "$CONF_DIR"
ls -la "$CONF_DIR"
grep -n "conf/conf.d" "$CONF"
```

如果该目录里还有别的站点文件，确认没有重复的 `server_name` 再继续。

## 4. 先放 HTTP 配置，签证书

```bash
install -m 644 wego.conf.http-first "$CONF_DIR/wego.conf"
$NGINX -t -c "$CONF"
$NGINX -s reload -c "$CONF"
```

确认配置真的被加载（不要只看 `nginx -t`，通配符匹配不到文件时它也会静默通过）：

```bash
$NGINX -T -c "$CONF" | grep -n "wego.conf"
```

签发五个域名的证书：

```bash
mkdir -p /var/www/certbot
certbot certonly --webroot -w /var/www/certbot \
  -d sso.xzyang.cn \
  -d mockup.xzyang.cn \
  -d cad.xzyang.cn \
  -d quiz.xzyang.cn \
  -d files.xzyang.cn \
  --agree-tos -m 你的邮箱@example.com --non-interactive
```

成功后确认证书存在：

```bash
ls /etc/letsencrypt/live/sso.xzyang.cn/
```

## 5. 换成 HTTPS 配置

```bash
install -m 644 wego.conf "$CONF_DIR/wego.conf"
$NGINX -t -c "$CONF"
$NGINX -s reload -c "$CONF"
```

访问：

```text
https://sso.xzyang.cn
https://mockup.xzyang.cn
https://cad.xzyang.cn
https://quiz.xzyang.cn
```

## 6. 前端必须用 HTTPS 重新打包

只换 Nginx 不够：前端构建时已经把 `http://...` 写进静态文件了，必须重新打包。

本地 `deploy\deploy.env` 改成：

```env
BASE_DOMAIN=xzyang.cn
ENABLE_TLS=1
LETSENCRYPT_EMAIL=你的邮箱@example.com
```

然后双击 `deploy\build-bundle.bat` 重新打包，上传 `wego-bundle.tar.gz`。

服务器上覆盖解压后，确认 `config/deploy.env` 也是 `BASE_DOMAIN=xzyang.cn`、`ENABLE_TLS=1`，再重启后端让 SSO 入口地址更新为 https：

```bash
cd /opt/others/deployWego/wego
tar -xzf wego-bundle.tar.gz -C .
./centos-start.sh
```

`centos-start.sh` 会自动执行 `update-app-urls.sh`，把 SSO 里三个系统的入口改成 https。

## 7. 注意

- **不要再运行 `./install-nginx.sh`**：它写的是 `/etc/nginx/conf.d/wego.conf`，而这里用的是自定义 `conf.d`，它管不到本文件；重新打包后也不要手工把 `nginx/wego.conf` 复制过来，那会变回 HTTP 配置。
- `files.xzyang.cn` 反代到 `127.0.0.1:9000`。如果 MinIO 不在本机，把 `wego.conf` 里该处 `proxy_pass` 改成真实地址。
- 如果最终不用 `xzyang.cn` 而是 `www.xzyang.cn`，把两个配置文件里的 `sso.xzyang.cn` 等整体替换，certbot 命令同步修改。
- 证书续期：HTTP 80 的 `/.well-known/acme-challenge/` 已保留，`certbot renew` 可正常使用。

## 常见问题

### certbot 报 `SERVFAIL looking up CAA`

这是 DNS 校验的偶发问题，不是 Nginx 配置问题。当前 `xzyang.cn` 没有 CAA 记录（允许签发），权威 NS 是 `dns21/dns22.hichina.com`。

- 脚本失败后等待 60 秒会自动重试一次
- 仍然失败就等 5–10 分钟再执行 `./issue-https.sh 邮箱`
- Let's Encrypt 对同一域名每小时最多 5 次失败校验，不要连续快速重试
- 排查可执行：
  ```bash
  yum install -y bind-utils
  dig @dns21.hichina.com xzyang.cn CAA +norecurse
  dig @dns22.hichina.com xzyang.cn CAA +norecurse
  dig @dns21.hichina.com quiz.xzyang.cn CAA +norecurse
  ```
  正常应返回 `NOERROR` 且没有 CAA 记录；如果某个权威 IP 返回 SERVFAIL，联系阿里云 DNS 支持或更换 NS。
