# render-markdown 阅读与编辑

Neovim 0.12.5 · render-markdown.nvim `8e87953`。打开 Markdown 后会自动渲染标题、列表、表格和代码块。渲染改变屏幕显示，文件中保存的仍是 Markdown 文本。

| 想做什么 | 普通模式操作 |
| --- | --- |
| 在源码与渲染之间切换 | 在 Markdown 窗口依次按 **反斜杠、m**（`\m`）。它调用全局开关，再按一次切回 |
| 只切换当前文档 | `:RenderMarkdown buf_toggle` |
| 明确打开／关闭当前文档的渲染 | `:RenderMarkdown buf_enable` ／ `:RenderMarkdown buf_disable` |
| 边写边对照渲染结果 | `:RenderMarkdown preview` 在侧面打开预览。在预览窗口执行 `:close` 收起 |
| 查看光标行周围更多源码 | `:RenderMarkdown expand` 扩大显示源码的范围，`:RenderMarkdown contract` 缩小 |

阅读长段落时可用 `gj`／`gk` 按屏幕上的折行移动。预览图片或 Mermaid 用 [Snacks 的 `\i`](snacks.nvim.help.md)。在 [Agentic 侧栏](agentic.nvim.help.md) 中，局部按键 `\m` 会打开模型选择器。

内置帮助见 `:help render-markdown-commands`。
