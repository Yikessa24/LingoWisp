# HoldTranslate 开发记录

## 2026-10-23 · 环境与设计
- 空目录启动；本机 macOS 26.6.2 / Apple Silicon，Xcode 27.1 / Swift 6.4，目标 macOS 15+。
- GitHub CLI 已在允许联网的环境验证账号 Yikessa24，可创建私人仓库。
- 核查 Apple Translation 官方文档及本地 SDK：macOS 15 使用 SwiftUI translationTask 管理 Session 生命周期；macOS 26 专有 API 必须 availability guard。
- 采用只读 NSEvent 监听、异步 AX 获取选区、NaturalLanguage 判断、非激活 NSPanel。无模拟复制、无屏幕录制、无第三方服务。
- 语言包缺失时引导用户主动在设置窗口下载；正常翻译浮窗不激活应用。

## 当前状态
- 已完成可运行原生应用、设备端翻译、浮窗、设置和权限引导；源代码已首次推送私人仓库 https://github.com/Yikessa24/HoldTranslate 。
- 最新 Release universal 1.0.1 构建成功；30 项自动化测试和 5 组真实翻译视觉集成验证通过。
- 用户已在 TextEdit 亲自操作并确认出现正确译文气泡；其他应用的全局硬件输入端到端验证仍待完成。
- 无 Developer ID 签名或公证。已知限制、具体证据及剩余场景见 docs/TESTING.md。

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

## 2026-10-23 · 第二轮稳定性与真实系统测试
- 扩大到 22 项自动化测试，全部通过。实际捕获并修复「任务开始前取消，仍写回语言对」的竞态；关闭时同时清除译文状态。
- 超时覆盖语言检测、语言包查询及翻译全过程；过期结果不能复活请求。NaturalLanguage / DictionaryServices 移到 actor 执行，避免阻塞 UI。
- TextEdit 实测发现 ⇧⌘T 与其格式转换命令冲突；兼容快捷键调整为 ⌃⌥⌘T，保留只读监听。
- 修复松键发生在 AX 读取完成之前的关闭行为，以及移动鼠标无法缩短原关闭计时器的问题。
- 用户已授权后，系统设置 AX 树确认 HoldTranslate 开关开启。后续重新 ad-hoc 签名的构建 AXIsProcessTrusted 再次为 false；本机没有有效代码签名身份。需要最终构建重新授权，不能绕过系统安全检查。
- 显式 --smoke-test 使用固定合成英文，真实 Translation availability 返回 needsDownload；浮窗不改变前台应用，canBecomeKey 为 false。诊断报告不含原文/译文。
- 真正的系统语言下载 sheet 已呈现，英中两个语言资源下载已请求；尚未完成，不宣称真实翻译通过。
- CUA 工具检查系统设置的一次调用异常阻塞约 7 小时 55 分钟。执行时间不等同于开发时间；未绕过平台限制。
- 老 Release 进程驻留约 8 小时：0.0% CPU、RSS 26,144 KiB、累计 CPU 0.91 秒。期间可能包含睡眠，仅作为驻留观察。
- 应用恢复打开会显示设置；新增原生绘制图标，界面支持按应用启动参数检查浅/深色。

## 2026-10-23 · 最终视觉与端到端验证
- 英语和简体中文系统资源下载完成；真实 TranslationSession 返回非空译文，首次烟雾测试确认前台未改变、panel 不能成为 key window。
- 根据用户确认，移除旧辅助功能记录后添加当前实际路径，应用内部显示「辅助功能已授权」。关闭/重开旧开关不足以刷新旧 ad-hoc 签名。
- CUA 可以向后台窗口发送事件，不能把这些操作视作系统全局硬件输入。用户亲自操作 TextEdit 测试文件并回复「出现了正确译文气泡」，该项标为用户实测通过。
- 独立 VisualHarness 使用生产面板及真实翻译响应；不修改主应用或用户偏好，不读取用户文档，输出实际 NSHostingView 渲染 PNG。
- 视觉测试发现两行英文译文错误进入 270pt 滚动区，已改为按实际字体测量决定滚动。回归结果：英译中 358×128pt，中译英 358×152pt，长译文 358×379pt。
- 最终视觉运行：英译中 0.88s，深色英译中 0.58s，中译英 0.63s，hello 0.61s，长文 1.47s；含 0.4s 捕获等待，不能视为纯引擎延迟。
- 繁体中文识别为 zh-Hant，但本机该资源未安装；真实路径正确返回 needsDownload，未宣称翻译通过。
- 最终回归：2026-10-23 09:15 CST，22 项 XCTest、0 失败；Debug/Release universal 编译，最终 Release 签名校验成功。
- 提交实际浅/深色、单词、长文和中译英渲染图；未验证的 Safari/Chrome/Notes/Pages/PDF/物理多屏等场景保留为待测。

## 2026-10-23 · 固定路径安装与交付准备
- 最终应用复制到 `/Users/felixyan/Applications/HoldTranslate.app`，签名完整性校验通过，约 2.3 MB。
- 安装后的固定合成英文烟雾测试真实返回 translated；前台应用保持不变，panelCanBecomeKey=false。移动后的辅助功能信任需刷新。
- 分发 ZIP：`build/Distribution/HoldTranslate-macOS.zip`，约 1.1 MB；SHA-256 为 `3ae82bcb6b4a278d8246a2ac3a84e937bbe21754c1ced083b90c2b0047007018`。
- 更新固定路径授权时，系统要求 Touch ID / 登录密码；已请用户亲自完成，不自动输入或绕过身份验证。
- 用户完成 Touch ID / 密码验证后，已把授权条目替换为 `/Users/felixyan/Applications/HoldTranslate.app`；应用内部再次确认「辅助功能已授权」。
- 最终安装版本的设置截图已更新；退出诊断实例后以普通启动方式重新运行，保持菜单栏驻留。
- GitHub 已核实为私人仓库；稳定性与视觉改进提交 e1b40de 已成功推送 main。

## 2026-10-23 · 1.0.1：用户反馈后的触发与微信兼容修复
- 用户反馈：网页、微信按住 Option 拖动无反应，先选中再按 ⌃⌥⌘T 可翻译；朋友圈截图显示 AX 选区不可访问。此前用户实测反馈没有分别确认这两条入口，不能据此宣称 Option 已通过。
- 检查发现安装目录和构建目录同时运行两个实例；已退出重复版本，并加入内核文件锁，阻止不同路径的第二实例启动。
- 全局 NSEvent 回调异步送达；原代码以回调时的 NSEvent.mouseLocation 代替事件坐标。改用 event.locationInWindow / window 转换，并用真实 down/up 位移补足缺失的中间拖动回调。
- 加入实际 InputMonitor.process 回归：不移动真实鼠标，输入历史坐标不同的鼠标事件，必须正确触发一次翻译。
- 增加 AXSelectedTextMarkerRange → AXStringForTextMarkerRange 查询和 focused window 候选，仍只读取选中文字。
- AX 不提供选区时显示明确的「复制选区并翻译」入口；自动复制兼容需要在设置明确开启，默认关闭。复制发给源 PID，检查系统安全输入及安全控件。
- 剪贴板兼容备份多个项目及全部可取得格式；跳过 promised / 过大 / 无法完整备份的数据；多次所有权变化不覆盖新剪贴板。取消请求仍完成有界恢复事务。不承诺异常或任意迟到的第三方复制能够完全恢复。
- 30 项自动化测试通过，包含多格式多项目恢复、原剪贴板不会被当作选区、并发改动保护、promise 拒绝、取消恢复和单实例释放。
- 真实英中双向、单词和长文 5 组视觉回归通过。Release universal 1.0.1 / build 2 编译与签名校验成功。
- 旧版保存在 `/private/tmp/HoldTranslate-1.0-rollback.app`；1.0.1 已更新到固定安装路径，系统辅助功能记录已刷新，应用内部确认授权；只运行一个进程。
- 使用显式 --input-report 临时排障，仅写最后一个阶段及授权/启用状态，不写文本、按键内容、应用标识或鼠标绝对位置。等待用户真实硬件输入复测，尚不把模拟事件测试视为 Option 修复实测通过。
