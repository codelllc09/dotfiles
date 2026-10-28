#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title GitHub Search
# @vicinae.icon 🐙
# @vicinae.mode silent
# @vicinae.keywords ["\\gh"]
# @vicinae.argument1 { "type": "text", "placeholder": "搜索仓库/代码", "percentEncoded": true }

xdg-open "https://github.com/search?q=$1&type=repositories"
