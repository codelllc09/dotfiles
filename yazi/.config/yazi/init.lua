-- ~/.config/yazi/init.lua —— 由 ~/.config/yazi/init.lua 软链到本文件
-- git.yazi：文件列表行尾显示 git 状态（ignored/untracked/unstaged/staged/added/deleted/updated）
require("git"):setup {
	-- 状态标识在行尾 linemode 中的排序权重
	order = 1500,
}

-- preview-epub.yazi：epub 封面预览（自动注册 application/epub+zip 规则，
-- 依赖 gnome-epub-thumbnailer，已安装）
require("preview-epub"):setup()

-- preview-cbz.yazi：.cbz/.cbr 漫画按页预览（依赖 unzip/unrar，已安装）
require("preview-cbz"):setup()
