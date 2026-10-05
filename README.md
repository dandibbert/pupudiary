# 噗噗手帐 · Pupudiary

可爱、好用的排便健康记录 App（iOS 17+，SwiftUI 原生）。参考了 PoopLog 的功能，但视觉上全部用 Q 版小豆子和抽象几何小图标，没有写实元素，看着不会不舒服。

<p align="center"><img src="Pupudiary/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="160" alt="App 图标"></p>

## 功能

| 模块 | 内容 |
| --- | --- |
| **今天** | 今日次数 / 距上次 / 连续记录天数；健康小结（吉祥物表情跟着状态变）；**一键记录**大按钮 + 按状态（偏干/理想/偏软/偏稀）一键记；最近 7 天彩色小格子；今天的记录列表 |
| **记录** | 时间（带「刚刚 / 15 分钟前…」快捷）、布里斯托 7 型（Q 版图标 + 一句话说明）、排出感受、分量、用时、颜色（可选）、不适症状（多选）、备注 |
| **日历** | 月历上每天用彩色小圆点显示状态，左右滑动切月；选中某天看详情，可补记过去的记录；也可以切到「全部列表」，左滑删除 |
| **趋势** | 7 / 30 / 90 天：总次数、日均、理想占比、最长间隔；每日次数柱状图、状态占比环形图、七型分布、常见时段；自动生成健康提示（几天没排、偏干/偏稀过多、出现血丝或异常颜色等） |
| **导出 / 导入** | PDF 健康报告（看医生时直接给医生看）、CSV 表格（Excel 不乱码）、JSON 完整备份；可导入本 App 的 JSON 备份，以及 **PoopLog 导出的 zip 备份**（重复导入不会产生重复记录） |
| **小组件** | 桌面小号：今日次数 + 「噗！记一下」按钮；桌面中号：7 天概览 + 四种状态一键记录；桌面大号：健康提示 + 7 天概览 + 今天的记录 + 一键记录；锁屏：圆形 / 矩形 / 行内；控制中心按钮（iOS 18+） |
| **一键记录** | App 首页、桌面小组件、控制中心、Siri（「用噗噗手帐记一下」）、快捷指令、iPhone 操作按钮 |
| **其他** | 每日提醒、面容 ID 隐私锁、触感反馈、深色模式、所有数据只存在本机 |

颜色约定（全 App 统一，一眼就能看懂）：🟠 偏干（1–2 型）· 🟢 理想（3–4 型）· 🟡 偏软（5 型）· 🔵 偏稀（6–7 型）。

## 安装（证书签名）

### 1. 拿到 IPA

每次推送代码，GitHub Actions（`.github/workflows/build.yml`）都会在 macOS 上编译出 **未签名的 `Pupudiary-unsigned.ipa`**：
仓库 → Actions → 最新一次 *Build IPA* → 底部 Artifacts 下载 `Pupudiary-ipa`。
推送 `v*` 标签（如 `v1.0.0`）时还会自动发布到 Releases。

### 2. 用你的证书签名，三选一

**A. 手机上用签名工具（最简单）**：把 IPA 和你的 `.p12` + `.mobileprovision` 导入 全能签 / 轻松签 / ESign 等工具签名安装。

**B. 电脑上**：爱思助手「IPA 签名」、Sideloadly、AltStore 等，用 Apple ID 或证书签名后安装。

**C. 让 GitHub Actions 直接签好**：在仓库 Settings → Secrets and variables → Actions 中添加：

| Secret | 内容 |
| --- | --- |
| `CERT_P12_BASE64` | `base64 -i cert.p12` 的输出 |
| `CERT_PASSWORD` | p12 密码 |
| `APP_PROFILE_BASE64` | App 描述文件的 base64 |
| `WIDGET_PROFILE_BASE64` | （可选）小组件描述文件的 base64，ID 为 `<App ID>.widget` |

之后每次构建会多出一个 `Pupudiary-signed.ipa`。在 Mac 上也可以手动运行：

```bash
scripts/resign.sh Pupudiary-unsigned.ipa cert.p12 'p12密码' app.mobileprovision [widget.mobileprovision] [输出.ipa]
```

脚本会自动把 Bundle ID 改成描述文件里的 ID；如果描述文件带 App Group，也会自动把 App 里用到的 App Group 改成它。

### 关于小组件和 App Group

App 会在运行时从签名用的描述文件里自动找出可用的 App Group，所以用 sign.lc、全能签等工具签名时不需要改任何东西，只要证书带 App Group、并且签名时**保留插件 / 扩展**即可。「我的 › 小组件数据」会显示是否已互通。

小组件和 App 通过 **App Group** 共享数据。想让小组件显示数据、一键记录写进 App：

- 描述文件对应的 App ID 需要开启 App Groups，并勾选一个 group（例如 `group.你的ID`）；小组件的 App ID 也要勾选同一个 group。
- 通配符描述文件（`TEAMID.*`）不能带 App Group：App 能正常用，但小组件看不到 App 的数据。
- 某些签名工具会丢掉扩展或 App Group，这种情况下 App 本身一切正常，「我的 › 小组件使用方法」里会给出提示。

> ⚠️ 更换签名 / Bundle ID 后系统会把它当成一个新 App，旧数据无法自动带过去。**重签前请先在「我的 › 导出记录」导出 JSON 备份**，装好后再导入。

## 自己编译

需要 macOS + Xcode 16 以上 + [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate
open Pupudiary.xcodeproj
```

在 `project.yml` 里可以修改 `APP_BUNDLE_ID`、`APP_GROUP_ID`、`DEVELOPMENT_TEAM`，然后直接用 Xcode 装到手机上。

## 项目结构

```
project.yml                 XcodeGen 工程描述
Shared/                     App 与小组件共用：数据模型、存储、统计、主题、Q 版图标、一键记录 Intent
Pupudiary/                  App：首页 / 记录 / 日历 / 趋势 / 设置 / 导出
PupudiaryWidget/            小组件 + 锁屏组件 + 控制中心
scripts/make_icon.py        生成 App 图标
scripts/resign.sh           证书重签名
```

数据以 JSON 保存在 App Group 容器里（`Pupudiary/records.json`），所有读写都通过 `NSFileCoordinator`，App 和小组件同时写入也不会丢数据。

---

本 App 仅用于日常记录，不能代替专业医疗建议。
