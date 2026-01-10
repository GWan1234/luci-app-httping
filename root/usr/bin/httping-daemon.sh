#!/bin/sh

DB_PATH=$(uci -q get httping.global.db_path) || DB_PATH="/etc/httping_data.db"

# 初始化数据库 (init.d 中也会做迁移，这里保留基本的创建)
if [ ! -f "$DB_PATH" ]; then
    sqlite3 "$DB_PATH" "CREATE TABLE monitor_log (id INTEGER PRIMARY KEY AUTOINCREMENT, server_name TEXT, timestamp INTEGER, duration REAL, type TEXT DEFAULT 'httping');"
    sqlite3 "$DB_PATH" "CREATE INDEX idx_ts ON monitor_log(timestamp);"
    sqlite3 "$DB_PATH" "CREATE INDEX idx_name ON monitor_log(server_name);"
    sqlite3 "$DB_PATH" "PRAGMA journal_mode=WAL;"
fi

get_uptime_ms() {
    awk '{printf "%.0f\n", $1 * 1000}' /proc/uptime
}

check_server() {
    local section="$1"
    local enabled
    local name
    local url
    local interval
    local type
    
    config_get enabled "$section" "enabled" "0"
    config_get name "$section" "name"
    config_get url "$section" "url"
    config_get interval "$section" "interval" "60"
    config_get type "$section" "type" "httping"

    if [ "$enabled" = "1" ] && [ -n "$url" ]; then
        LAST_RUN_FILE="/tmp/httping_${section}.last"
        NOW=$(date +%s)
        LAST_RUN=0
        [ -f "$LAST_RUN_FILE" ] && LAST_RUN=$(cat "$LAST_RUN_FILE")

        if [ $((NOW - LAST_RUN)) -ge "$interval" ]; then
            echo "$NOW" > "$LAST_RUN_FILE"
            
            (
                TS=$(date +%s)
                DURATION=""
                RETCODE=1

                if [ "$type" = "tcping" ]; then
                    # TCPing 处理逻辑
                    # 支持 IPv6 格式: [2001:db8::1]:80 或 host:port
                    if echo "$url" | grep -q "\["; then
                        HOST=$(echo "$url" | sed -n 's/.*\[\(.*\)\].*/\1/p')
                        PORT=$(echo "$url" | sed -n 's/.*\]:\(.*\)/\1/p')
                    else
                        HOST=$(echo "$url" | cut -d: -f1)
                        PORT=$(echo "$url" | cut -d: -f2)
                    fi
                    
                    # 如果没有指定端口，默认80
                    if [ -z "$PORT" ] || [ "$HOST" = "$PORT" ]; then
                        PORT=80
                    fi
                    
                    # 使用 Lua 解析 IP (支持 IPv4 和 IPv6)，排除 DNS 解析时间
                    TARGET_IP=$(lua -l nixio -e "local iter = nixio.getaddrinfo('$HOST'); if iter and iter[1] then print(iter[1].address) end")
                    
                    if [ -n "$TARGET_IP" ]; then
                        START_MS=$(get_uptime_ms)
                        
                        # 检测 IPv6 并添加 -6 参数
                        NC_OPTS="-z -w 2"
                        case "$TARGET_IP" in
                            *:*) NC_OPTS="$NC_OPTS -6" ;;
                        esac

                        nc $NC_OPTS "$TARGET_IP" "$PORT" >/dev/null 2>&1
                        RETCODE=$?
                        END_MS=$(get_uptime_ms)
                        
                        if [ $RETCODE -eq 0 ]; then
                            DURATION=$((END_MS - START_MS))
                        fi
                    else
                        # 解析失败
                        RETCODE=1
                    fi
                else
                    # HTTPing 处理逻辑 (原有逻辑)
                    RESULT=$(curl -L -k -s -o /dev/null -w "%{time_namelookup} %{time_total}" --max-time 5 "$url")
                    RETCODE=$?

                    if [ $RETCODE -eq 0 ]; then
                        T_DNS=$(echo "$RESULT" | awk '{print $1}')
                        T_TOTAL=$(echo "$RESULT" | awk '{print $2}')
                        DURATION=$(awk "BEGIN {print ($T_TOTAL - $T_DNS) * 1000}")
                    fi
                fi

                # 写入数据库
                if [ $RETCODE -eq 0 ] && [ -n "$DURATION" ]; then
                    sqlite3 "$DB_PATH" "INSERT INTO monitor_log (server_name, timestamp, duration, type) VALUES ('$name', $TS, $DURATION, '$type');"
                else
                    sqlite3 "$DB_PATH" "INSERT INTO monitor_log (server_name, timestamp, duration, type) VALUES ('$name', $TS, NULL, '$type');"
                fi
            ) &
        fi
    fi
}

while true; do
    ENABLED=$(uci -q get httping.global.enabled)
    if [ "$ENABLED" != "1" ]; then
        sleep 10
        continue
    fi

    # 加载 OpenWrt 函数库
    . /lib/functions.sh
    
    # 读取配置文件
    config_load "httping"
    
    # 遍历 server 节点
    config_foreach check_server "server"

    sleep 1
done
