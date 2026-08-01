# Mindful Timer for Windows

一个主动开启的正向计时悬浮钟：先写目的，再开始积累；需要时展开记事，结束后留下可继续使用的记录。

## 直接运行

双击：

```text
Start Mindful Timer.cmd
```

应用基于 Windows 自带的 PowerShell 5.1 与 WPF，不需要安装 .NET SDK、Node.js 或浏览器扩展。

如果 Windows 显示脚本运行提示，确认文件来自当前项目后再继续。启动脚本只运行同目录下的 `MindfulTimer.ps1`，不下载内容、不联网、不修改系统设置。

## 使用流程

1. 可以直接点击“查看笔记库”，不需要先填写目的；要开始新的积累时再写下具体目的。
2. 点击“开始积累”，窗口缩成始终置顶的正向计时器。
3. 点击右上角月亮/太阳图标，一键切换白天或黑夜主题。
4. 点击“展开记事”，记录链接、观察、问题或值得复用的细节。
5. 点击“结束并留下记录”。
6. 在完成页查看本次目的和时长，或打开应用内笔记库。

## 应用内笔记库

点击“查看笔记库”后可以：

- 按时间浏览当前草稿和已完成 Session
- 搜索目的或笔记正文
- 在右侧阅读完整记录
- 一键复制目的、时间和正文
- 必要时继续用记事本打开原始 `records.md`
- 笔记库本身不置顶，阅读时不会一直压住其他窗口

## 本地数据

首次运行后会在 `WindowsApp/data` 创建：

| 文件 | 用途 |
| --- | --- |
| `current-note.md` | 当前 Session 的自动保存草稿 |
| `draft.json` | 异常退出后的目的与笔记恢复信息 |
| `records.md` | 适合直接阅读和积累的历史记录 |
| `records.json` | 后续做搜索、统计或迁移时使用的结构化数据 |

应用不会上传这些内容。

## 操作细节

- 拖动顶部 `MINDFUL` 区域移动悬浮窗。
- 线性太阳/月亮按钮：切换白天/黑夜；应用会记住上次选择。
- 只有正在积累时计时窗口置顶；起始页、完成页和笔记库不置顶。
- `Enter`：在目的输入框中开始。
- `Ctrl + S`：立即保存当前笔记草稿。
- `Esc`：收起展开的记事区域。
- 关闭正在计时的窗口时，可选择保存、放弃或继续。

## 验证命令

只验证 XAML 能否加载：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\MindfulTimer.ps1 -ValidateOnly
```

渲染四个真实 WPF 状态：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\MindfulTimer.ps1 -RenderPreview
```

使用隔离目录验证计时、笔记、Markdown 和 JSON 归档：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\MindfulTimer.ps1 -SmokeTest -DataDirectory .\test-output\smoke-data
```
