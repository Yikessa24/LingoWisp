# HoldTranslate 开发记录

## 2026-10-23 · 环境与设计
- 空目录启动；本机 macOS 26.6.2 / Apple Silicon，Xcode 27.1 / Swift 6.4，目标 macOS 15+。
- GitHub CLI 已在允许联网的环境验证账号 Yikessa24，可创建私人仓库。
- 核查 Apple Translation 官方文档及本地 SDK：macOS 15 使用 SwiftUI translationTask 管理 Session 生命周期；macOS 26 专有 API 必须 availability guard。
- 采用只读 NSEvent 监听、异步 AX 获取选区、NaturalLanguage 判断、非激活 NSPanel。无模拟复制、无屏幕录制、无第三方服务。
- 语言包缺失时引导用户主动在设置窗口下载；正常翻译浮窗不激活应用。

## 实施中
- 原生 Xcode 工程、核心逻辑与测试、菜单栏和设置、翻译会话与浮窗。

## 待实际验证
- 编译、启动、核心自动化测试、空闲资源测量。
- 系统辅助功能授权后跨应用划词；语言包下载与真实翻译；多显示器。
- 不把编译成功或模拟数据界面视为真实端到端验证。

## 2026-10-23 · 第一轮实现与实际检查
- 完成原生菜单栏应用、设置、登录启动、只读事件监听、有界后台 AX 选区读取、语言策略、系统 Translation、非激活浮窗。
- Debug 已成功编译 arm64 + x86_64，应用实际启动；UI 自动化读取到真实设置页及「需要辅助功能权限」。
- 首轮 13 项核心测试发现：屏幕顶部边距漏夹取；NaturalLanguage 对 hello 置信度仅 0.13。已修正坐标上界，使用系统 DictionaryServices 辅助确认系统排名第一的英文短词，不把任意 ASCII 当英文。
- 核实系统词典：hello/translation/chat 有定义，xyzzy/asdjklqwe 无定义。不会将这些探针当作实际翻译成功。
- UI 工具首次连接耗时约 14 分钟；不推断为应用卡顿。
- 本机权限尚未授予，真实跨应用选择/翻译未验证。

## 2026-10-23 · 首次可运行交付
- Release universal（arm64/x86_64）构建成功，产物 `build/Distribution/HoldTranslate.app`，ad-hoc 签名校验成功。
- 13 项 XCTest 核心测试全部通过；语言、手势、三种屏幕排列的边界网格检查真实执行。
- 真实设置窗口已视觉检查；没有伪造翻译演示图。
- Git 初始化 main，目标 GitHub 仓库尚不存在，准备创建私人仓库。
