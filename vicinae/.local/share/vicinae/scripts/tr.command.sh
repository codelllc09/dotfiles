#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Translate (Baidu)
# @vicinae.icon 🌐
# @vicinae.mode silent
# @vicinae.keywords ["tr", "翻译", "fy"]
# @vicinae.argument1 { "type": "text", "placeholder": "要翻译的内容", "percentEncoded": true }

xdg-open "https://fanyi.baidu.com/#en/zh/$1"
