m = Map("httping", translate("网络延迟监控设置"))

s = m:section(NamedSection, "global", "global", translate("全局设置"))
s:option(Flag, "enabled", translate("启用监控"))
s:option(Value, "db_path", translate("数据库路径"), translate("默认: /etc/httping_data.db (建议x86设备保持默认)"))

btn = s:option(Button, "_clear", translate("管理数据"))
btn.inputtitle = translate("清除所有历史数据")
btn.inputstyle = "remove" 
btn.write = function(self, section)
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "httping", "clear_data"))
end

ts = m:section(TypedSection, "server", translate("服务器节点列表"))
ts.template = "cbi/tblsection"
ts.addremove = true
ts.anonymous = true

ts:option(Flag, "enabled", translate("启用"))
ts:option(Value, "name", translate("显示名称"))
ts:option(Value, "url", translate("检测URL (http/https)"))
ts:option(Value, "interval", translate("检测间隔(秒)"))

return m