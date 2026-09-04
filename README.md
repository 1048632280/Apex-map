# Apex Ranked Rotation

一个轻量的 Apex Legends 排位地图轮换单页。

## 功能

- 当前地图
- 下一张地图
- 三张地图轮换时间轴
- 倒计时与进度环
- 24 小时制
- API 失败时显示离线状态，不使用模拟数据
- Node.js 和 Go 两套服务端
- 服务端首屏注入真实数据

## 数据

服务端请求：

```text
https://apexranked.com/api/ranked-map
```

服务端会在启动时尝试获取数据，并在运行期间每分钟同步一次；地图切换时还会额外刷新。浏览器只访问服务端，不会遇到跨域问题。

如果接口暂时失败，服务会保留最后一次成功获取的真实数据，同时将状态标记为 `OFFLINE`；如果从未成功获取过数据，则显示占位符。

## Docker 镜像

GitHub Actions 会在推送到 `main` 分支或创建 `v*` 标签时构建并推送两套镜像：

```text
ghcr.io/<GitHub用户名或组织>/apex-map-node
ghcr.io/<GitHub用户名或组织>/apex-map-go
```

工作流文件：

```text
.github/workflows/publish-images.yml
```

首次使用 GHCR 时，需要在 GitHub Packages 中将对应镜像设置为公开，或者在服务器登录 GHCR：

```bash
echo "$CR_PAT" | docker login ghcr.io -u <GitHub用户名> --password-stdin
```

## Docker Compose

两份 compose 的功能相同，只是后端语言不同。**同一台服务器只启动其中一份**，因为它们都使用 `4173` 端口。

### Node.js 版本

```bash
export GHCR_OWNER=<GitHub用户名或组织>
docker compose -f docker-compose.node.yml pull
docker compose -f docker-compose.node.yml up -d
```

### Go 版本

```bash
export GHCR_OWNER=<GitHub用户名或组织>
docker compose -f docker-compose.go.yml pull
docker compose -f docker-compose.go.yml up -d
```

查看服务状态：

```bash
docker compose -f docker-compose.go.yml ps
curl http://127.0.0.1:4173/healthz
```

Node 版本只需要把上面的文件名替换为 `docker-compose.node.yml`。

宝塔中将网站反向代理到：

```text
http://127.0.0.1:4173
```

## 本地运行

Node.js：

```bash
node server.js
```

Go：

```bash
go run .
```

默认监听 `4173` 端口，也可以通过环境变量修改：

```bash
PORT=8080 node server.js
PORT=8080 go run .
```

## 文件

- `index.html` 入口页面
- `styles.css` 样式
- `app.js` 页面逻辑
- `server.js` Node.js 服务端
- `main.go` Go 服务端
- `Dockerfile.node` Node.js 镜像构建文件
- `Dockerfile.go` Go 镜像构建文件
- `docker-compose.node.yml` Node.js compose
- `docker-compose.go.yml` Go compose
- `manifest.webmanifest` PWA 配置
- `image/` 地图与图标资源

## 资源来源

- 轮换数据来自 ApexRanked
- 地图图片来自 EA 官方地图页
- 图标使用 Apex 风格的简洁三角 A 形象
