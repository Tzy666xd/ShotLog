# ShotLog

macOS 原生的照片拍摄行为分析工具。读相册里的 EXIF，再叠一层系统内置的 Vision 模型，回答一个问题：**我这些照片到底是怎么拍出来的。**

全部计算在本机完成，不联网、不上传。

## 能做什么

- **逐张解析**：机型、镜头、等效焦距、光圈、快门、ISO、曝光补偿、白平衡、闪光灯，以 3×3 小卡片呈现
- **画面识别**：场景标签、人脸数量、画面美学评分、文档/截图判别（`VNClassifyImageRequest` / `VNDetectFaceRectanglesRequest` / `VNCalculateImageAestheticsScoresRequest`，模型权重在系统里，app 不打包任何文件）
- **统计画像**：拍摄习惯健康度、星期 × 时段热力图、拍摄量趋势、参数分布（ISO / 光圈 / 快门 / 焦距 / 曝光）、设备与焦段、题材与光线、失误统计、自动洞察
- **拍摄提示**：按相册整体统计给出可执行建议；**成长记录**：每天一条参数快照
- 4 档列表密度（紧凑 / 适中 / 网格 / 画廊）、两两对比视图

## 构建

需要 Xcode（脚本固定使用 `/Applications/Xcode.app/Contents/Developer`，装在别处就改脚本里的 `TOOLCHAIN`）。

```bash
./build-and-sign.sh --check   # 只编译到 /tmp，不动桌面 App，用于语法自检
./build-and-sign.sh           # 编译 + 签名，产物覆盖 ~/Desktop/ShotLog.app
```

脚本里替你处理了两个 macOS 上的坑：

1. **必须带 `-load-plugin-library .../libSwiftUIMacros.dylib`**。sandbox 下 `swift-plugin-server` 起不来，不加这行会报 `StateMacro could not be found`。
2. **必须用开发证书签名，不能用 ad-hoc**。ad-hoc 的签名身份绑定二进制哈希，每次重编译 macOS 都会当成一个新 app，相册授权随之丢失；开发证书绑定的是证书本身，重编译不影响已授予的权限，授权一次就够。

第一次在新机器上跑时，如果 `~/Desktop/ShotLog.app` 还不存在，脚本会用 `Resources/` 里的 `Info.plist` 和图标现搭一个 bundle（已存在的 bundle 不会被覆盖）。

换签名身份或改产物路径：

```bash
security find-identity -v -p codesigning          # 先看本机有哪些可用身份

SHOTLOG_SIGN_ID="Apple Development: 你的名字 (XXXXXXXXXX)" \
SHOTLOG_APP=~/Applications/ShotLog.app \
./build-and-sign.sh
```

## 环境

- 开发与测试环境：macOS 27 / Xcode 27。代码按 macOS 13+ 的 SwiftUI API 编写；美学评分与「实用图」判别用的 `VNCalculateImageAestheticsScoresRequest` 带 `@available(macOS 15)` 保护，低版本会自动降级为无该维度
- 纯 SwiftUI 单文件，**无任何第三方依赖**

## 隐私

- 只读相册，不修改、不导出照片
- 不发起任何网络请求（iCloud 照片的下载走的是系统 Photos 框架，不是 app 自己联网）
- 解析结果缓存在 `~/Library/Application Support/ShotLog/entries.json`，每日快照在 `growth.json`；删掉这两个文件等于清空记录，工具栏 `⋯ › 清空解析结果` 也会清缓存

## 仓库结构

```
ShotLog/ShotLog.swift   全部源码（单文件，约 3000 行）
Resources/              Info.plist（含相册用途说明）+ 应用图标，首次构建时用于搭 bundle
build-and-sign.sh       编译 + 签名脚本
legacy/                 早期分叉版留档，功能未合并，仅作参考
```

## 已知限制

- 单次扫描上限 500 张（硬编码），取的是相册里最近的 500 张
- **等效焦距靠查表**：手机既不写 `FocalLengthIn35mmFilm`，也不写 `FocalPlaneXResolution`，crop factor 无从推算。已为相册里出现过的机型建了对照表，未收录的机型会按镜头角色退化成典型值（13 / 16 / 24 / 90mm）
- 解析缓存没有失效策略：在系统相册里删掉的照片，列表里仍会保留
- 文档 / 截图会被排除出题材、光线、设备、焦段等分布统计（否则占比整个失真），但仍在列表里可见
