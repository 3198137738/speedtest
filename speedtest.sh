#!/usr/bin/env bash

set -u

# 强制交互信息输出到当前终端，避免 SSH 会话 stdout 被重定向时看不到结果
if [ -w /dev/tty ]; then
    exec >/dev/tty 2>&1
fi

WORKERS="${WORKERS:-16}"
LOG_DIR="/var/log/speedtest"
mkdir -p "$LOG_DIR"

echo "=================================="
echo "   单机带宽持续下载测试"
echo "=================================="
echo

read -rp "请输入测试文件 URL: " URL

if [ -z "$URL" ]; then
    echo "URL 不能为空"
    exit 1
fi

echo
echo "请选择运行模式："
echo "1) 随机运行"
echo "2) 24 小时不间断"
echo
read -rp "请选择 [1/2]: " MODE

case "$MODE" in
    1)
        DURATION=$((1800 + RANDOM % 19801))
        MODE_NAME="random"
        ;;
    2)
        DURATION=86400
        MODE_NAME="24h"
        ;;
    *)
        echo "输入错误"
        exit 1
        ;;
esac

NOW=$(date +%Y%m%d_%H%M%S)
LOG="$LOG_DIR/${MODE_NAME}_${NOW}.log"
PID_FILE="/var/run/speedtest.pid"
END_TIME=$(( $(date +%s) + DURATION ))

worker() {
    while [ "$(date +%s)" -lt "$END_TIME" ]; do
        curl \
            -4 \
            -L \
            --fail \
            --silent \
            --show-error \
            --connect-timeout 15 \
            --retry 3 \
            --retry-delay 1 \
            -o /dev/null \
            "$URL"
        sleep 1
    done
}

run_test() {
    echo "==================================" >> "$LOG"
    echo "开始时间: $(date)" >> "$LOG"
    echo "URL: $URL" >> "$LOG"
    echo "并发: $WORKERS" >> "$LOG"
    echo "持续时间: $DURATION 秒" >> "$LOG"
    echo "限速: 无" >> "$LOG"
    echo "==================================" >> "$LOG"

    for i in $(seq 1 "$WORKERS"); do
        worker >> "$LOG" 2>&1 &
    done

    wait
    echo "结束时间: $(date)" >> "$LOG"
}

RUNNER=(bash -c)
if command -v setsid >/dev/null 2>&1; then
    RUNNER=(setsid bash -c)
fi

nohup "${RUNNER[@]}" "$(declare -f worker run_test); \
URL='$URL'; \
WORKERS='$WORKERS'; \
DURATION='$DURATION'; \
END_TIME='$END_TIME'; \
LOG='$LOG'; \
run_test" \
>/dev/null 2>&1 &

PID=$!
echo "$PID" > "$PID_FILE"

sleep 1

echo
if kill -0 "$PID" 2>/dev/null; then
    echo "=================================="
    echo "测试已后台启动"
    echo "=================================="
    echo
    echo "PID      : $PID"
    echo "模式     : $MODE_NAME"
    echo "运行时间 : $DURATION 秒"
    echo "并发数   : $WORKERS"
    echo "限速     : 无"
    echo "日志     : $LOG"
    echo
    echo "查看进程："
    echo "ps -p $PID -o pid,etime,cmd"
    echo
    echo "查看日志："
    echo "tail -f $LOG"
    echo
    echo "停止测试："
    if command -v setsid >/dev/null 2>&1; then
        echo "kill -- -$PID"
    else
        echo "kill $PID"
    fi
else
    echo "启动失败，请查看日志：$LOG"
    exit 1
fi
