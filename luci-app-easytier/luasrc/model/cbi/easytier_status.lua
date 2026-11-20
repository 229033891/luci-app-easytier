local http = luci.http

m = Map("easytier", translate("ET Status"))
m.pageaction = false

-- 状态卡片
m:section(SimpleSection).template = "easytier/easytier_status"

-- 连接信息卡片
m:section(SimpleSection).template = "easytier/easytier_cli"

return m
