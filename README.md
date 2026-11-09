# wego 工作区

四个独立业务仓库的统一工作区，只跟踪本地启动脚本和部署工具；四个业务仓库仍各自独立提交。

## 目录

```text
.
├── deploy/                  # 打包、部署、HTTPS、发版脚本
├── start.bat / start.sh     # 本地启动四个系统（开发）
├── stop.bat / stop.sh
├── wego_sso/                # 独立仓库：单点登录
├── wego_3d_texture/         # 独立仓库：包装样机
├── wego_fingertip_3d_web/   # 独立仓库：三维建模
└── wego_quiz_3d/            # 独立仓库：答题闯关
```

带 `.ps1` 的脚本是 PowerShell 版本，按需使用。

## 首次克隆

```bash
git clone git@github.com:xxhxj/wego_workspace.git wego
cd wego
git clone git@github.com:xxhxj/wego_sso.git
git clone git@github.com:xxhxj/wego_3d_texture.git
git clone git@github.com:xxhxj/wego_fingertip_3d_web.git
git clone git@github.com:xxhxj/wego_quiz_3d.git
```

## 本地开发

Windows 双击 `start.bat`，Linux/macOS 执行 `./start.sh`；停止用对应的 `stop` 脚本。各系统地址与端口见 `deploy/README.md`。

## 生产部署

- 本地打包：`deploy/build-bundle.bat`（Windows）
- 服务器发版：把 `wego-bundle.tar.gz` 放到运行目录后执行 `deploy/release.sh`
- 生产环境使用 Nginx + pm2，不在服务器构建前端
- HTTPS 证书与续期：`deploy/nginx-https/`

完整说明见 `deploy/README.md` 和 `deploy/bundle-template/README.md`。

## 安全

`deploy/deploy.env` 和各后端的 `.env` 含数据库、MinIO、Quiz 密钥，已在 `.gitignore` 排除，不要提交或外发。
