# Markview 的 Typst 预览

Neovim 0.12.5 · markview.nvim `v29.0.0`。打开 `.typ` 文件即可在正文里预览。普通模式或插入模式下，光标所在行显示源码。移到另一行，原先那行会恢复渲染。

| 想做什么 | 操作 |
| --- | --- |
| 切换当前文件的预览 | 在 Typst 窗口执行 `:Markview toggle` |
| 切换光标附近显示源码的混合模式 | `:Markview hybridToggle` |
| 并排查看源码和预览 | `:Markview splitToggle`。再次执行可收起，也可用 `:Markview splitClose` |
| 查看插件处理记录 | `:Markview traceShow` 打开日志窗口，在里面按 `q` 关闭 |

这套配置把 Markview 用于 Typst。Markdown 的显示开关见 [render-markdown 指南](render-markdown.nvim.help.md)。在支持图像占位符的 Kitty 中，装有 `typst` 时，公式由 Snacks 排版。

内置帮助见 `:help markview.nvim`。
