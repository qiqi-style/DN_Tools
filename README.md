# DN_Tools

DN_Tools 是一个 Bash 控制台工具，用来统一安装和管理 Docker Compose 项目，并为项目生成 Nginx 反向代理配置。

## 核心功能

- 扫描内置 Docker 项目和 `/app/<project_id>` 自定义项目
- 安装、启动、停止、更新、卸载 Docker Compose 项目
- 显示已安装项目、运行状态、内网/外网地址和连通状态
- 记录安装时使用的镜像标记，例如 `ghcr.io/basketikun/chatgpt2api:latest`
- 生成、预览、手动编辑、写入、删除 Nginx 反代配置
- 更新时确认备份项目目录；当天已有同项目备份时可选择跳过备份，并可同步备份 Nginx 配置
- 在“备份管理”中按项目浏览备份版本、备份日期、`/app` 目录与安装状态；可解压、恢复并安装或删除指定备份

## 必要环境

- Bash
- root/sudo 权限
- Docker 和 Docker Compose
- Nginx
- `curl`、`git`
- `vim`，仅手动编辑 Nginx 配置时需要
- 默认应用目录：`/app`

首次进入控制台时，可从“运行环境菜单”安装 Docker CE（含 Buildx 与 Docker Compose v2）和 Nginx。目前支持 Ubuntu、Debian 和 CentOS；Docker 使用 Docker 官方软件源，Nginx 使用系统软件源。

安装 Nginx 后，工具会创建 `/app/nginx/conf`，并将其链接到系统配置目录 `/etc/nginx`。可以通过 `/app/nginx/conf` 编辑 `nginx.conf`、`conf.d/` 等配置；这些文件仍由系统软件包安装的 Nginx 从 `/etc/nginx` 加载。若该路径已存在，工具会保留现有内容并提示，不会覆盖。

## 安装

一键安装：

```bash
bash <(curl -sL https://raw.githubusercontent.com/qiqi-style/DN_Tools/main/install.sh)
```

手动安装：

```bash
git clone https://github.com/qiqi-style/DN_Tools.git
cd DN_Tools
sudo ./install.sh
```

安装后运行：

```bash
dntool
```

## 删除 DN_Tools 脚本

只删除工具脚本和全局命令：

```bash
sudo rm -rf /opt/DN_Tools
sudo rm -f /usr/local/bin/dntool
```

如果安装时自定义过路径，请按实际路径删除：

```bash
sudo rm -rf <INSTALL_DIR>
sudo rm -f <BIN_PATH>
```

这只会删除 DN_Tools 本身，不会删除 `/app/<project_id>` 里的 Docker 项目、运行数据、Nginx 配置或备份文件。

## 自定义 Docker 项目准备

把项目放到：

```text
/app/<project_id>/docker-compose.yml
```

推荐同时准备：

```text
# 脚本显示参考项
/app/<project_id>/dntool-config/project.conf

# nginx反代配置文件
/app/<project_id>/dntool-config/<project_id>.conf
```

`project.conf` 示例：

```bash
PROJECT_NAME="my-app"
DESCRIPTION="自定义 Docker 服务"
PROJECT_URL="https://github.com/example/my-app"
IMAGE_VERSION=""
HEALTH_URL="http://127.0.0.1:3000/"
PUBLIC_URL=""
```

准备要点：

- `docker-compose.yml` 中应明确暴露本机访问端口
- 如果有密钥、密码、Token，请先改掉示例占位值
- `HEALTH_URL` 用于内网连通检测
- `<project_id>.conf` 可作为项目专属 Nginx 模板
- 自定义项目放在 `/app`，不要放进仓库的 `docker/` 目录

## 内置项目

- `chatgpt2api`
- `cli-proxy`
- `new-api`

内置项目模板在仓库 `docker/<project_id>/` 下，项目说明和 Nginx 模板放在各自的 `dntool-config/` 目录。

## 常用环境变量

```bash
TARGET_BASE_DIR=/app dntool
NGINX_DIR_OVERRIDE=/etc/nginx dntool
SKIP_NGINX_RELOAD=1 dntool
DN_TOOLS_ALLOW_NON_ROOT=1 ./start.sh
DN_TOOLS_CHECK_CONNECT_TIMEOUT=1 DN_TOOLS_CHECK_MAX_TIME=2 dntool
DN_TOOLS_PROBE_CONCURRENCY=8 dntool
```

项目列表中的 Docker 状态、内网和外网检测会并发执行，多个不可达地址不会再逐个累加等待时间。可通过 `DN_TOOLS_CHECK_CONNECT_TIMEOUT` 和 `DN_TOOLS_CHECK_MAX_TIME` 调整单个地址的连接和总超时秒数，通过 `DN_TOOLS_PROBE_CONCURRENCY` 调整同时检测的项目数。

## 注意事项

- 一键安装会更新工具目录 `/opt/DN_Tools`
- 用户项目、运行数据和配置应放在 `/app/<project_id>`
- 删除项目、Docker volumes、Nginx 配置前会二次确认
- 公网访问建议通过 Nginx 反代，并提前准备好域名和 SSL 证书
