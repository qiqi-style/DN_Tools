# DN_Tools

DN_Tools 是一个用于服务器 Docker 项目部署、管理和 Nginx 反向代理配置的 Bash 控制台工具。

它适合把常用 AI 代理、接口转换、API 聚合等 Docker Compose 项目整理成模板，然后通过统一菜单安装到 `/app/<project_id>`，再按项目生成 Nginx 反代配置。

## 功能特点

- 启动时检测 Docker、Docker Compose、Nginx 和 `/app` 应用目录状态
- 自动扫描 `docker/*/docker-compose.yml` 展示内置 Docker 项目
- 支持安装、启动、停止、更新、卸载、备份 Docker Compose 项目
- 支持读取和手动维护 `project.conf` 项目信息
- 支持自定义 `/app/<project_id>/docker-compose.yml` 项目
- 支持 Nginx 反代模板生成、预览、写入、删除和 reload
- Nginx 配置写入后会备份到项目目录，并回写 `PUBLIC_URL`
- 默认保留安全占位值，首次部署前会提醒替换密钥和密码
- 复用 `scripts/theme.sh` 的 qiqi-style 终端主题

## 内置项目

当前内置 Docker 模板：

- `new-api`：OpenAI 兼容接口聚合、分发与管理服务
- `cli-proxy`：CLI Proxy API 代理与远程管理服务
- `chatgpt2api`：ChatGPT 接口转换与图像生成服务

内置项目位于：

```text
docker/<project_id>/
├── docker-compose.yml
├── project.conf
└── .env.example
```

## 一键安装

推荐使用下面这种方式一键安装：

```bash
bash <(curl -sL https://raw.githubusercontent.com/qiqi-style/DN_Tools/main/install.sh)
```

非 root 用户可以使用：

```bash
curl -fsSL https://raw.githubusercontent.com/qiqi-style/DN_Tools/main/install.sh | sudo bash
```

重复运行一键安装会重新拉取项目并覆盖 `/opt/DN_Tools`。用户已经安装或自定义的 Docker 项目应放在 `/app/<project_id>`，不会被一键安装覆盖。

不要把自定义 Docker 项目放在 `/opt/DN_Tools/docker`，该目录只用于仓库内置模板，升级时会随仓库刷新。

安装完成后，在任意目录运行：

```bash
dntool
```

## 手动安装

```bash
git clone https://github.com/qiqi-style/DN_Tools.git
cd DN_Tools
sudo ./install.sh
```

如果只是本地测试菜单，可以直接运行：

```bash
sudo ./start.sh
```

## 使用流程

### 1. 环境检测

运行 `dntool` 后，脚本会检测：

- Docker 是否存在
- Nginx 是否存在
- `/app` 应用目录是否存在

当前 Docker 和 Nginx 自动安装功能是占位提示，需要先手动安装依赖。

### 2. Docker 项目安装

进入主菜单后选择：

```text
[ 1 ] Docker 项目安装
```

脚本会先检测 `/app/<project_id>` 是否已有对应项目；如果没有，再从 `/opt/DN_Tools/docker/<project_id>` 的内置模板复制到：

```text
/app/<project_id>/
```

后续再次运行一键安装只会更新工具本身，正常不会覆盖 `/app/<project_id>` 中的运行数据和用户配置。

如果项目包含 `.env.example`，会自动生成 `.env`。首次启动前请把 `DN_TOOLS_CHANGE_ME_*` 替换成你自己的强密码或密钥。

### 3. Docker 项目管理

进入：

```text
[ 2 ] Docker 项目管理
```

可以查看项目详情：

- 项目名称
- 功能说明
- 项目地址
- 运行目录
- 容器名称
- 镜像版本
- 当前运行状态
- 内网访问地址
- 外网访问地址

支持操作：

- 启动 / 重启项目
- 停止项目
- 卸载项目
- 更新项目并自动备份
- 配置 Nginx 反代
- 手动更新 `project.conf`

### 4. Nginx 反代设置

进入：

```text
[ 3 ] Nginx 反代设置
```

脚本会让你选择项目和模板，然后填写：

- 绑定域名
- 上游主机
- 上游端口
- HTTPS 监听端口
- SSL 证书路径
- SSL 私钥路径
- 上传大小限制

写入前会展示配置预览。确认后写入：

```text
<nginx_dir>/conf.d/<project_id>.conf
```

同时备份到：

```text
/app/<project_id>/nginx-config/<project_id>.conf
```

并回写：

```bash
PUBLIC_URL="https://your-domain.com"
```

## 自定义 Docker 项目

把自己的项目放到：

```text
/app/<project_id>/docker-compose.yml
```

然后重新进入 Docker 安装菜单，脚本会自动扫描 `/app/*/docker-compose.yml`，并以 `991`、`992`、`993`... 的选项展示用户自定义项目。

推荐同时提供：

```text
/app/<project_id>/project.conf
```

示例：

```bash
PROJECT_NAME="my-app"
DESCRIPTION="自定义 Docker 服务"
PROJECT_URL="https://github.com/example/my-app"
ACCESS_SCHEME="http"
ACCESS_HOST="127.0.0.1"
ACCESS_PORT="3000"
ACCESS_PATH="/"
HEALTH_URL="http://127.0.0.1:3000/"
NGINX_TEMPLATE="default"
PUBLIC_URL=""
```

## Nginx 模板

模板目录：

```text
nginx-config/templates/
```

内置模板：

- `default`：通用 Web 反代
- `ai-stream`：AI 流式输出、长连接、大文件上传
- `strict`：更严格的安全头和 TLS 配置

模板固定占位符：

```text
{{SERVER_NAME}}
{{LISTEN_PORT}}
{{UPSTREAM_HOST}}
{{UPSTREAM_PORT}}
{{SSL_CERT}}
{{SSL_KEY}}
{{CLIENT_MAX_BODY_SIZE}}
```

## 目录结构

```text
DN_Tools/
├── install.sh
├── start.sh
├── scripts/
│   ├── theme.sh
│   ├── common.sh
│   ├── docker_manage.sh
│   └── nginx_manage.sh
├── docker/
│   ├── new-api/
│   ├── cli-proxy/
│   └── chatgpt2api/
└── nginx-config/
    ├── nginx.conf
    └── templates/
```

## 常用环境变量

安装脚本：

```bash
INSTALL_DIR=/opt/DN_Tools bash install.sh
BIN_PATH=/usr/local/bin/dntool bash install.sh
REPO_URL=https://github.com/qiqi-style/DN_Tools.git bash <(curl -sL https://raw.githubusercontent.com/qiqi-style/DN_Tools/main/install.sh)
```

运行脚本：

```bash
TARGET_BASE_DIR=/app dntool
NGINX_DIR_OVERRIDE=/etc/nginx dntool
SKIP_NGINX_RELOAD=1 dntool
```

## 注意事项

- 请先安装 Docker、Docker Compose 和 Nginx
- 请在启动项目前替换所有 `DN_TOOLS_CHANGE_ME_*` 占位值
- 默认只绑定 `127.0.0.1` 端口，公网访问建议通过 Nginx 反代
- 用户自定义项目请放在 `/app/<project_id>`，不要直接放在 `/opt/DN_Tools/docker`
- 一键安装会重新拉取并覆盖 `/opt/DN_Tools`，请不要在该目录保存用户配置
- 删除项目、删除 volume、删除 Nginx 配置前脚本会二次确认
- `.env`、运行数据、日志和备份文件默认不会提交到 Git
