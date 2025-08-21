# MikroTik RouterOS v7+
# 1) NetFlow v9 export (flows; does NOT include NAT map on all models)
/ip traffic-flow set enabled=yes cache-entries=8192 active-flow-timeout=30m inactive-flow-timeout=15s
/ip traffic-flow target add address=<GRAYLOG_IP> port=2055 v9-template-refresh=20m v9-template-timeout=10m

# 2) IPFIX (if supported on your model/ROS). Prefer IPFIX for richer fields
# /ip traffic-flow ipfix set enabled=yes
# /ip traffic-flow target add address=<GRAYLOG_IP> port=4739 version=ipfix

# 3) NAT hit logging (heavy!) — only if you must track pre/post-NAT on RouterOS
# Use a dedicated rule with a narrow match (e.g. only CGNAT pool), otherwise logs will be massive.
/ip firewall nat add chain=srcnat action=masquerade out-interface=<WAN> log=yes log-prefix=nat_hit:
# Send logs to Graylog (Syslog)
/system logging action add name=remote target=remote remote=<GRAYLOG_IP> remote-port=1514 src-address=<ROUTER_IP>
/system logging add topics=firewall prefix=fw action=remote

# 4) DHCP lease + PPPoE logs → correlate MAC↔IP↔User
/system logging add topics=pppoe,account prefix=pppoe action=remote
/system logging add topics=dhcp,info prefix=dhcp action=remote
