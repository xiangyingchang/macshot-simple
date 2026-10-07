# MacShot Simple

中文 | [English](README.en.md)

一个只做截图和简单标注的 macOS 菜单栏应用。基于 [sw33tLie/macshot v4.3.0](https://github.com/sw33tLie/macshot/tree/v4.3.0) 精简，采用 AppKit 和系统截图 API，无第三方依赖。

## 使用

1. 打开应用，在系统设置中允许 MacShot Simple 录制屏幕。
2. 按 `⌘⇧X`，或点击菜单栏图标选择“截图”。菜单显示当前快捷键；已有安装会保留之前的组合。
3. 鼠标悬停会预览窗口。单击选中窗口，或拖动框选区域。
4. 拖动选区内部移动，拖动八个小方块调整边缘。点击标注工具开始标注；再次点击同一工具返回移动选区模式。
5. 点击绿色勾号复制并结束，或点击保存按钮导出 PNG。

六种标注：矩形、椭圆、箭头、画笔、马赛克、文字。笔画采用细、中、粗三档，颜色采用六个常用色。支持撤销、重做。

- `Esc`：取消截图。文字输入中先取消当前文字。
- `Enter`：复制并结束。文字输入中先确认文字，`Shift+Enter` 换行。
- `⌘C`：复制并结束；`⌘S`：保存；`⌘Z` / `⌘⇧Z`：撤销 / 重做。文字输入时采用系统编辑快捷键。
- 右键：选中后返回重新框选，未选中时退出。
- 选择模式下双击选区：复制并结束。

多屏分别显示截图画布，选区限制在单个屏幕。保留原始屏幕像素分辨率；尺寸标签显示输出像素。

不包含录屏、上传、账号、历史记录、OCR、翻译、长截图、贴图、美化、自动更新或独立图片编辑器。交互参考常见聊天工具，不承诺与微信或飞书完全一致。

## 构建

```sh
git clone https://github.com/xiangyingchang/macshot-simple.git
cd macshot-simple
```

需要 macOS 12.3 或以上，以及支持 macOS 26 SDK 的 Xcode（源码包含有可用性保护的新版截图 API）。没有额外包需要下载。

```sh
scripts/build-simple.sh
open 'build/Build/Products/Release/MacShot Simple.app'
```

默认本机架构、临时签名。Intel 和 Apple Silicon 通用构建：

```sh
SIMPLE_ARCHS='arm64 x86_64' scripts/build-simple.sh
```

使用自己的开发者证书签名：

```sh
SIMPLE_SIGNING_IDENTITY='你的签名身份' scripts/build-simple.sh
```

也可用 Xcode 打开 `macshot.xcodeproj`，选择 `macshot` scheme，设置自己的签名团队。应用标识默认为 `local.macshot.simple`；正式公开发行前选择自己的标识。改变应用标识或签名身份可能需要重新授予屏幕录制权限。

构建脚本不会自动安装、上传、发布或修改系统权限。默认临时签名构建未经苹果公证，首次打开可能需要在系统设置中允许。面向普通用户的正式安装包仍需开发者自行签名和公证。

## 验证

```sh
scripts/run-tests.sh
```

测试不需要屏幕录制权限，覆盖选区坐标、Retina 裁剪、标注渲染、马赛克、撤销重做、三档粗细和工具栏外观。真实系统授权、快捷键手感、输入法和多屏操作需要手工体验。

退出正在运行的应用后，可执行本地截图诊断：

```sh
'build/Build/Products/Release/MacShot Simple.app/Contents/MacOS/MacShot Simple' --check-capture
```

诊断在内存中读取屏幕、绘制标注并编码 PNG/TIFF，仅输出屏幕数量、尺寸和成功状态；不保存屏幕图像，不修改剪贴板。它可能触发系统的屏幕录制权限提示。

## 代码结构

- `Capture/ScreenCaptureManager.swift`：沿用并收紧上游截图引擎，保留新旧系统路径。
- `Model/CaptureGeometry.swift`：选区、窗口坐标和像素裁剪。
- `Model/Annotation.swift`：六种标注、渲染和撤销记录。
- `UI/CaptureCanvas.swift`：框选、鼠标交互和系统文字编辑器。
- `UI/CaptureToolbar.swift`：工具栏、粗细选项和颜色。
- `UI/DesignTheme.swift`：统一颜色、图标和间距；设计原则见 [DESIGN.md](DESIGN.md)。
- `Services/`：一个全局快捷键、键盘布局匹配、少量设置和本地诊断。
- `AppDelegate.swift`：菜单栏、截图生命周期、复制和保存。

## 开源与致谢

本项目是 MacShot 的修改版本，与上游独立维护。保留上游作者 sw33tLie 的署名及 GPL-3.0 许可证。基于上游的代码和图标资源仍按原许可证使用，详见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。当前为 0.1.1 开发试用版，已公开源码；尚未提供经过苹果公证的安装包。问题反馈请使用 [GitHub Issues](https://github.com/xiangyingchang/macshot-simple/issues)，安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。
