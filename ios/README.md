# iOS App（SwiftUI，纯本地）

Apex 排位地图轮换的 iOS 客户端。**不连后端、不需要 API key**：轮换是「有序序列 + 固定时长 + 一个锚点时间」，全部在本地推算。最低支持 **iOS 15**。

设计参考 Kelivo 的 SurfaceLadder（低对比分层 + hairline + 克制的字号阶梯），地图大图作为内容主体。

## 结构

```
ios/
  project.yml                 XcodeGen 工程定义（没有二进制 .xcodeproj）
  Shared/                     主 App 与小组件共用
    Model.swift               地图、配置、轮换计算、格式化
    Theme.swift               明暗色板、字号阶梯、卡片修饰
    SharedConfig.swift        App Group 共享配置、图片缓存
  ApexRotation/               主 App
    ApexRotationApp.swift
    ConfigStore.swift         配置与主题状态
    MainView.swift            主界面
    CalibrationView.swift     校准与设置
  ApexRotationWidgets/        小组件（8 个）
    ApexWidgets.swift         WidgetBundle + TimelineProvider + 8 个配置
    ApexWidgetViews.swift     8 个组件视图
  ApexRotationTests/
```

地图素材不复制，直接引用仓库里的 `public/image/*.webp` 和 `*.png`。

## 主界面

- 顶部居中：Apex 图标 + `APEX LEGENDS` 字样
- 左上：校准；右上：明暗切换（带过渡动画，选择持久化）
- 当前地图大图 + 名称 + 剩余时间 + 进度
- 下一张卡片
- 「之后」2–4 行（按屏幕高度自动决定行数）

**主界面固定一屏、不滚动**：hero 吃掉剩余空间，排程行数按屏幕高度在 2/3/4 之间切换，只有校准页可以滚动。

## 小组件（8 个）

| kind | 尺寸 | 内容 |
|---|---|---|
| `small_current` | 小 | 地图大图 + 名称 + 倒计时 + 进度条 |
| `small_countdown` | 小 | 地图大图 + 超大倒计时 |
| `small_ring` | 小 | 地图大图 + 大号圆环进度 |
| `small_ring_name` | 小 | 地图名放在圆环中央 |
| `medium_split` | 中 | 左图 + 右侧实色面板（下一张） |
| `medium_dual` | 中 | 整图左右分栏 |
| `large_list` | 大 | 上图 + 下方 3 行排程 |
| `large_overlay` | 大 | 整图 + 底部叠层 |

倒计时全部用 `Text(timerInterval:)`，由系统托管走秒；进度环在组件里是静态的，随 timeline 刷新。timeline 前 1 小时每 10 分钟、之后每 30 分钟 / 每小时给一个条目，保证圆环不会长时间停在 0%。

## 数据共享（重要）

主 App 与小组件通过 **App Group** `group.com.apexmap.rotation` 共享 `rotation.json`。

- 免费 Apple ID + 手动重签的链路下，App Group 是否可用存在不确定性。
- 如果安装失败或组件一直显示「打开 App 校准」，说明 entitlement 没保留，需要付费账号或改用其他同步方式。

## 在 Windows 上

只能改代码，无法编译。验证靠 CI：

- 推送 `main` 或手动 `Run workflow` 触发 [ios.yml](../../.github/workflows/ios.yml)
- 先跑模拟器构建 + 单元测试（抓编译错误和算法回归）
- 再产出**无签名 IPA** 作为 artifact

## 在 Mac 上

```bash
brew install xcodegen
cd ios
xcodegen generate
open ApexRotation.xcodeproj
```

## 安装到 iPhone（Windows）

1. 装 iTunes（Apple 官网下载版，不要 Microsoft Store 版）
2. 装 [Sideloadly](https://sideloadly.io/)，USB 连接 iPhone
3. 选择 CI 下载的 `ApexRotation-unsigned.ipa`，填 Apple ID，开始签名安装
4. iPhone「设置 → 通用 → VPN 与设备管理」信任开发者
5. 打开 App，首次进入弹出校准页

免费 Apple ID 的签名 **7 天过期**，到期后重新装一次。

## 已知限制

- **没有通知系统**：不请求通知权限，也没有换图提醒。
- 组件倒计时在 iOS 16+ 用 `Text(timerInterval:)`；iOS 15 用 `Text(结束时间, style: .timer)`。两者都由系统托管走秒，不需要组件刷新；区别是 15 的格式由系统决定（可能没有前导 0）。
- 轮换时长默认 **4 小时 30 分**，在校准页用滚轮按「小时 + 分钟」调整。
- 赛季换图、官方临时改排程后需要重新校准一次。
- 轮换时长默认 60 分钟；以校准页填的「结束时间」为准，时长只用于推算后续槽位。

## 数据来源

Apex Legends Status（网页版使用）。iOS 版不请求该接口，地图名称与素材来自本仓库 `public/image/`。
