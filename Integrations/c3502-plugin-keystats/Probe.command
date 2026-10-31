#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
echo "按回车开始 30 秒测试，然后操作键盘与鼠标。计数每 5 秒更新。"
read -r
mkdir -p ../../build/C3502
PROBE_RESULT=0
node examples/probe.mjs --request-permission | tee ../../build/C3502/manual-probe.log || PROBE_RESULT=$?
echo "测试结束。按回车关闭。"
read -r

exit "$PROBE_RESULT"
