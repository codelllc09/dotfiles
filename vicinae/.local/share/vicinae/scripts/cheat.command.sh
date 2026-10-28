#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Cheat Sheet (cht.sh)
# @vicinae.icon 📚
# @vicinae.mode fullOutput
# @vicinae.keywords ["\\cheat", "\\cht"]
# @vicinae.argument1 { "type": "text", "placeholder": "主题：tar、git/rebase、python:json、docker…" }

# ?T = 纯文本输出（去 ANSI 色码）
curl -s --max-time 15 "https://cht.sh/$1?T"
