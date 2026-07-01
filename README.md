# DN_Tools

DN_Tools 是一个 Bash 控制台工具，用来统一安装和管理 Docker Compose 项目，并为项目生成 Nginx 反向代理配置。

## 核心功能

- 扫描内置 Docker 项目和 `/app/<project_id>` 自定义项目
- 安装、启动、停止、更新、卸载 Docker Compose 项目
- 显示已安装项目、运行状态、内网/外网地址和连通状态
- 记录安装时使用的镜像标记，例如 `ghcr.io/basketikun/chatgpt2api:latest`
- 生成、预览、手动编辑、写入、删除 Nginx 反代配置
- 更新前备份项目目录，并可同步备份 Nginx 配置

## 必要环境

- Bash
- root/sudo 权限
- Docker 和 Docker Compose
- Nginx
- `curl`、`git`
- `vim`，仅手动编辑 Nginx 配置时需要
- 默认应用目录：`/app`

Docker 和 Nginx 自动安装目前只是提示功能，需要先按服务器环境安装好依赖。

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
```

## 注意事项

- 一键安装会更新工具目录 `/opt/DN_Tools`
- 用户项目、运行数据和配置应放在 `/app/<project_id>`
- 删除项目、Docker volumes、Nginx 配置前会二次确认
- 公网访问建议通过 Nginx 反代，并提前准备好域名和 SSL 证书
