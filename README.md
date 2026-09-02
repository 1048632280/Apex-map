# Apex Ranked Rotation

一个轻量的 Apex Legends 排位地图轮换单页。

## 功能

- 当前地图
- 下一张地图
- 轮换时间轴
- 倒计时
- 24 小时制
- API 失败时显示离线状态，不使用模拟数据

## 使用

1. 复制 `config.example.js` 为 `config.local.js`
2. 填入自己的 Apex Legends Status API Key
3. 用本地静态服务器打开 `index.html`

## 文件

- `index.html` 入口页面
- `styles.css` 样式
- `app.js` 逻辑
- `manifest.webmanifest` PWA 配置
- `image/` 地图与图标资源

## 资源来源

- 地图图来自 EA 官方地图页
- 轮换数据来自 Apex Legends Status
- 图标候选来自公开图标站点，最终保留的是标准三角 A 形象

## 说明

`config.local.js` 已加入 `.gitignore`，不会提交到仓库。
