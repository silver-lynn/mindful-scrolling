# Mindful Scrolling · Windows Public Beta

一个给 AI 时代 builder 的轻量悬浮计时器：在开始浏览或研究前写下目的，正向计时，随手记录，最后把真正值得带走的东西留进笔记库。

![Mindful Timer 白天模式](WindowsApp/preview/light-01-start.png)

## 下载

从 [Releases](https://github.com/silver-lynn/mindful-scrolling/releases) 下载最新的 `MindfulTimer-Windows-v0.5.zip`，解压后双击：

```text
Start Mindful Timer.cmd
```

应用基于 Windows 自带的 PowerShell 5.1 与 WPF，不需要安装运行库，也不联网。

> 当前是未签名的公开测试版。Windows 可能显示脚本或来源提示；请只从本仓库 Releases 下载，并核对 Release 中提供的 SHA-256。

## 它解决什么

Mindful 不阻止你打开内容，而是在注意力被带走之前保留一个明确意图：

```text
写下目的 → 正向计时 → 边看边记 → 结束并归档 → 回到笔记库
```

## 当前功能

- 起始页可直接打开笔记库，也可以填写目的后开始积累
- 正向计时期间自动置顶；其他状态与笔记库不置顶
- 计时过程中展开记事，草稿每两秒自动保存
- 完成后记录目的、时长、时间和笔记
- 应用内笔记库支持搜索、详情阅读和复制全文
- 白天／黑夜主题一键切换并记住选择
- 所有内容只保存在本机

![Mindful Notes 黑夜模式](WindowsApp/preview/dark-05-notes-library.png)

## 系统要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1

## 本地数据

首次运行后，程序会在 `WindowsApp/data` 创建草稿、Markdown 和 JSON 记录。该目录已被 Git 忽略，不会进入仓库或 Release。

完整说明见 [WindowsApp/README.md](WindowsApp/README.md)，隐私说明见 [PRIVACY.md](PRIVACY.md)。

## 公测范围

当前版本不检测浏览器或目标程序，也不做强制拦截。它先验证最小闭环是否有效：一个具体目的，是否能帮助用户在浏览结束后留下可复用的内容。

欢迎通过 Issues 反馈使用体验与问题。

