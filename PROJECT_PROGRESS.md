# 项目进度

2026-11-07：PR #2 审核反馈修订，详见 [EXECUTION_PLAN.md](EXECUTION_PLAN.md)。

- T1 / T3 已完成：双击完成截图贡献与 [PR #2](https://github.com/xiangyingchang/macshot-simple/pull/2)。
- T4 / T5 已完成：处理新建空文本编辑器截获第二次点击；保留选词、编辑后删空及 marked text 的原生行为。56 项测试通过，Release 构建及签名验证通过，diff 检查通过。
- T6 已完成：修复 835e3fa 已推送，原 PR 描述已更新，等待维护者复审；不合并或发布。
- T2 待验证：真实鼠标、中文输入法、多屏尚未实测。新增测试区分完整窗口分发和按实际 hitTest 目标分发，反向验证旧编辑器路径失败。
- 接续入口：执行计划 T4–T6；CaptureCanvas.swift 和 CaptureCanvasTests.swift；分支 fix/double-click-copy-anywhere。
