#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Bilibili Search
# @vicinae.icon 📺
# @vicinae.mode silent
# @vicinae.keywords ["bili", "b站"]
# @vicinae.argument1 { "type": "text", "placeholder": "搜索视频", "percentEncoded": true }

xdg-open "https://search.bilibili.com/all?keyword=$1"
