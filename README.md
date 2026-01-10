# luci-app-httping

LuCI support for Network Latency Monitor.
Supports **HTTPing** and **TCPing** modes.

## Features

- **HTTP/HTTPS Monitor**: Check web server latency accurately (excluding DNS lookup time).
- **TCP Monitor (New)**: Check TCP port connectivity and latency (e.g., `192.168.1.1:22` or `google.com:80`).
- **Visual Graph**: Interactive ECharts graph to view historical latency trends.
- **Data Persistence**: Uses SQLite to store monitoring data.
- **Auto Cleaning**: Automatically cleans up old data (configurable... manual for now).

## Installation

```bash
opkg update
opkg install luci-app-httping
```

## Configuration

Go to **Network** -> **Network Latency** (or Services -> Network Latency depending on menu layout).

1. Enable the global service.
2. Add server nodes.
3. Select **Ping Type**:
   - **HTTPing**: Enter a valid URL (e.g., `https://www.google.com`).
   - **TCPing**: Enter `Host:Port` (e.g., `1.1.1.1:53` or `github.com:443`).
4. Set check interval.

## Version History

- **1.0.13**: Added TCPing support; Added database migration for ping types.
- **1.0.12**: Initial stable release with HTTPing.