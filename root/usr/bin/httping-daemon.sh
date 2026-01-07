#!/bin/sh

# 数据库路径，默认为 /etc/httping_data.db
DB_PATH=$(uci -q get httping.global.db_path) || DB_PATH="/etc/httping_data.db"

# 初始化数据库
if [ ! -f "$DB_PATH" ]; then
    sqlite3 "$DB_PATH" "CREATE TABLE monitor_log (id INTEGER PRIMARY KEY AUTOINCREMENT, server_name TEXT, timestamp INTEGER, duration REAL);"
    sqlite3 "$DB_PATH" "CREATE INDEX idx_ts ON monitor_log(timestamp);"
    sqlite3 "$DB_PATH" "CREATE INDEX idx_name ON monitor_log(server_name);"
    # x86 性能优化：开启 WAL 模式
    sqlite3 "$DB_PATH" "PRAGMA journal_mode=WAL;"
fi

while true; do
    # 检查全局启用状态
    ENABLED=$(uci -q get httping.global.enabled)
    if [ "$ENABLED" != "1" ]; then
        sleep 10
        continue
    fi

    # 遍历配置
    config_load() {
        local section="$1"
        local enabled
        local name
        local url
        local interval
        
        config_get enabled "$section" "enabled" "0"
        config_get name "$section" "name"
        config_get url "$section" "url"
        config_get interval "$section" "interval" "60"

        if [ "$enabled" = "1" ] && [ -n "$url" ]; then
            # 检查时间间隔
            LAST_RUN_FILE="/tmp/httping_${section}.last"
            NOW=$(date +%s)
            LAST_RUN=0
            [ -f "$LAST_RUN_FILE" ] && LAST_RUN=$(cat "$LAST_RUN_FILE")

            if [ $((NOW - LAST_RUN)) -ge "$interval" ]; then
                echo "$NOW" > "$LAST_RUN_FILE"
                
                # 异步测速
                (
                    RESULT=$(curl -s -o /dev/null -w "%{time_namelookup} %{time_total}" --max-time 5 "$url")
                    RETCODE=$?
                    TS=$(date +%s)

                    if [ $RETCODE -eq 0 ]; then
                        T_DNS=$(echo "$RESULT" | awk '{print $1}')
                        T_TOTAL=$(echo "$RESULT" | awk '{print $2}')
                        DURATION=$(awk "BEGIN {print ($T_TOTAL - $T_DNS) * 1000}")
                        sqlite3 "$DB_PATH" "INSERT INTO monitor_log (server_name, timestamp, duration) VALUES ('$name', $TS, $DURATION);"
                    else
                        sqlite3 "$DB_PATH" "INSERT INTO monitor_log (server_name, timestamp, duration) VALUES ('$name', $TS, NULL);"
                    fi
                ) &
            fi
        fi
    }

    . /lib/functions.sh
    config_load "httping"
    config_foreach config_load "server"

    sleep 1
done