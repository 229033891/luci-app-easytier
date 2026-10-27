local nixio = require "nixio"

m = Map("easytier")

-- easytier-core general settings
s=m:section(TypedSection, "easytier")
s.addremove=false
s.anonymous=true

switch = s:option(Flag, "enabled", translate("Enable"))
switch.rmempty = false

etcmd = s:option(ListValue, "etcmd", translate("Startup Method"),
        translate("Please note to set the RPC port to 15888"))
etcmd.default = "etcmd"
etcmd:value("etcmd", translate("Default"))
etcmd:value("config", translate("Configuration File"))
etcmd:value("web", translate("Web Configuration"))

et_config = s:option(TextValue, "et_config", translate("Configuration File"),
        translate("The configuration file is located at /etc/easytier/config.toml<br>"
                .. "The command-line startup parameters and the parameters in this configuration file are not synchronized<br>"
                .. "Make sure to specify the TUN interface name and port to enable automatic firewall allowance"))
et_config.rows = 18
et_config.wrap = "off"
et_config:depends("etcmd", "config")

et_config.cfgvalue = function(self, section)
    return nixio.fs.readfile("/etc/easytier/config.toml") or ""
end
et_config.write = function(self, section, value)
    local dir = "/etc/easytier/"
    local file = dir .. "config.toml"
    -- 检查目录是否存在，如果不存在则创建
    if not nixio.fs.access(dir) then
        nixio.fs.mkdir(dir)
    end
    nixio.fs.writefile(file, value:gsub("\r\n", "\n"))
end

web_config = s:option(Value, "web_config", translate("Web Server Address"),
        translate("Web configuration server address. (-w parameter)<br>"
                .. "For a self-hosted Web server, use the format: udp://server_address:22020/username<br>"
                .. "For the official Web server, use the format: username"))
web_config.placeholder = "admin"
web_config:depends("etcmd", "web")

network_name = s:option(Value, "network_name", translate("Network Name"),
        translate("The network name used to identify this VPN network (--network-name parameter)"))
network_name.password = true
network_name.placeholder = "easytier-name"
network_name.maxlength = 64
network_name:depends("etcmd", "etcmd")

network_secret = s:option(Value, "network_secret", translate("Network Secret"),
        translate("Network secret used to verify whether this node belongs to the VPN network (--network-secret parameter)"))
network_secret.password = true
network_secret.placeholder = "easytier-password"
network_secret.maxlength = 128
network_secret:depends("etcmd", "etcmd")

ip_dhcp = s:option(Flag, "ip_dhcp", translate("Enable DHCP"),
        translate("IP address will be automatically determined and assigned by ET, starting from 10.0.0.1 by default. "
                .. "Warning: When using DHCP, if an IP conflict occurs in the network, the IP will be automatically changed. (-d parameter)"))
ip_dhcp:depends("etcmd", "etcmd")

ipaddr = s:option(Value, "ipaddr", translate("Interface IP Address"),
        translate("The IPv4 address of this VPN node. If left empty, this node will only forward packets and will not "
                .. "create a TUN device. (-i parameter)"))
ipaddr.datatype = "ip4addr"
ipaddr.placeholder = "10.0.0.1"
ipaddr:depends("etcmd", "etcmd")

ip6addr = s:option(Value, "ip6addr", translate("Interface IPV6 Address"),
        translate("ipv6 address of this vpn node, can be used together with ipv4 for dual-stack operation"
                .. "(--ipv6 parameter)"))
ip6addr.datatype = "ip6addr"
ip6addr.placeholder = "2001:db8::1"
ip6addr:depends("etcmd", "etcmd")

peeradd = s:option(DynamicList, "peeradd", translate("Peer Nodes"),
        translate("Initial connected peer nodes (-p parameter)<br>"
                .. "Public server status check: <a href='https://uptime.easytier.cn' target='_blank'>"
                .. "Click here to check</a>"))
peeradd:depends("etcmd", "etcmd")

--[=[
external_node = s:option(Value, "external_node", translate("Shared Node Address"),
        translate("Use a public shared node to discover peer nodes, same function as the parameter above (-e parameter)"))
external_node.default = ""
external_node.placeholder = "tcp://public.easytier.top:11010"
external_node:value("tcp://public.easytier.top:11010", translate("Official Server - tcp://public.easytier.top:11010"))
external_node:depends("etcmd", "etcmd")
]=]

proxy_network = s:option(DynamicList, "proxy_network", translate("Subnet Proxy"),
        translate("Export the local network to other peers in the VPN, allowing access to other devices in the current LAN (-n parameter)"))
proxy_network:depends("etcmd", "etcmd")

listenermode = s:option(ListValue, "listenermode", translate("Listener Port"),
        translate("OFF: Do not listen on any port, only connect to peer nodes (--no-listener parameter)<br>"
                .. "If used purely as a client (not as a server), you can choose not to listen on a port"))
listenermode:value("ON", translate("Listen"))
listenermode:value("OFF", translate("Do Not Listen"))
listenermode.default = "ON"
listenermode:depends("etcmd", "etcmd")

tcp_port = s:option(Value, "tcp_port", translate("TCP/UDP Port"),
        translate("TCP/UDP protocol port number: 11010 means TCP/UDP will listen on port 11010.<br>"
                .. "If this is the Web configuration in the config file, please fill in the same listening port for firewall allowance."))
tcp_port.datatype = "range(1,65535)"
tcp_port.default = "11010"
tcp_port:depends("listenermode", "ON")
tcp_port:depends("etcmd", "web")

ws_port = s:option(Value, "ws_port", translate("WS Port"),
        translate("WS protocol port number: 11011 means WS will listen on port 11011.<br>"
                .. "If this is the Web configuration in the config file, please fill in the same listening port for firewall allowance."))
ws_port.datatype = "range(1,65535)"
ws_port.default = "11011"
ws_port:depends("listenermode", "ON")
ws_port:depends("etcmd", "web")

wss_port = s:option(Value, "wss_port", translate("WSS Port"),
        translate("WSS protocol port number: 11012 means WSS will listen on port 11012.<br>"
                .. "If this is the Web configuration in the config file, please fill in the same listening port for firewall allowance."))
wss_port.datatype = "range(1,65535)"
wss_port.default = "11012"
wss_port:depends("listenermode", "ON")
wss_port:depends("etcmd", "web")

wg_port = s:option(Value, "wg_port", translate("WG Port"),
        translate("WireGuard protocol port number: 11011 means WG will listen on port 11011.<br>"
                .. "If this is the Web configuration in the config file, please fill in the same listening port for firewall allowance."))
wg_port.datatype = "range(1,65535)"
wg_port.placeholder = "11011"
wg_port:depends("listenermode", "ON")
wg_port:depends("etcmd", "web")

quic_port = s:option(Value, "quic_port", translate("QUIC Port"),
        translate("If this is the Web configuration in the config file, please fill in the same listening port for firewall allowance."))
quic_port.datatype = "range(1,65535)"
quic_port:depends("listenermode", "ON")
quic_port:depends("etcmd", "web")

local model = nixio.fs.readfile("/proc/device-tree/model") or ""
local hostname = nixio.fs.readfile("/proc/sys/kernel/hostname") or ""
model = model:gsub("\n", "")
hostname = hostname:gsub("\n", "")
local device_name_default = (model ~= "" and model) or (hostname ~= "" and hostname) or "OpenWrt"
device_name_default = device_name_default:gsub(" ", "_")
hostname_opt = s:option(Value, "desvice_name", translate("Hostname"),
        translate("The hostname used to identify this device (--hostname parameter)"))
hostname_opt.placeholder = device_name_default
hostname_opt.default = device_name_default
hostname_opt:depends("etcmd", "etcmd")
hostname_opt:depends("etcmd", "web")

uuid = s:option(Value, "uuid", translate("UUID"),
        translate("Unique identifier used to recognize this device when connecting to the web console, for issuing configuration files"))
uuid.rows = 1
uuid.wrap = "off"
uuid:depends("etcmd", "web")
uuid.cfgvalue = function(self, section)
    return nixio.fs.readfile("/etc/easytier/et_machine_id") or ""
end
uuid.write = function(self, section, value)
    nixio.fs.writefile("/etc/easytier/et_machine_id", value:gsub("\r\n", "\n"))
end

log = s:option(ListValue, "log", translate("Program Log"),
        translate("Runtime log is located at /tmp/easytier.log. View it in the log section above.<br>"
                .. "Levels: Error < Warning < Info < Debug < Trace"))
log.default = "off"
log:value("off", translate("Off"))
log:value("error", translate("Error"))
log:value("warn", translate("Warning"))
log:value("info", translate("Info"))
log:value("debug", translate("Debug"))
log:value("trace", translate("Trace"))

return m
