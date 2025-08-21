#!/usr/bin/env bash
set -euo pipefail

API="${GRAYLOG_HTTP_EXTERNAL_URI%/}/api"
ADMIN_USER="admin"
ADMIN_PASS="admin"

# jq is required
if ! command -v jq >/dev/null 2>&1; then
  echo "[*] Installing jq ..."
  apt-get update -y && apt-get install -y jq
fi

echo "[*] Waiting for Graylog API ..."
for i in {1..60}; do
  if curl -fsS "${API}/system/cluster/nodes" -u "$ADMIN_USER:$ADMIN_PASS" >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

types_json="$(curl -fsS "${API}/system/inputs/types" -u "$ADMIN_USER:$ADMIN_PASS")"

# Helper to find type id by human name substring
find_type() {
  local needle="$1"
  echo "$types_json" | jq -r --arg n "$needle" '.[] | select(.name | test($n;"i")) | .type' | head -n1
}

SYSLOG_UDP_TYPE="$(find_type "Syslog UDP")"
SYSLOG_TCP_TYPE="$(find_type "Syslog TCP")"
RAW_UDP_TYPE="$(find_type "Raw/Plaintext UDP")"
GELF_UDP_TYPE="$(find_type "GELF UDP")"
GELF_TCP_TYPE="$(find_type "GELF TCP")"
NETFLOW_UDP_TYPE="$(find_type "NetFlow UDP")"
IPFIX_UDP_TYPE="$(find_type "IPFIX UDP")"
BEATS_TCP_TYPE="$(find_type "Beats")"

echo "[*] Detected types:"
echo "  SYSLOG_UDP_TYPE = $SYSLOG_UDP_TYPE"
echo "  SYSLOG_TCP_TYPE = $SYSLOG_TCP_TYPE"
echo "  GELF_UDP_TYPE   = $GELF_UDP_TYPE"
echo "  GELF_TCP_TYPE   = $GELF_TCP_TYPE"
echo "  NETFLOW_UDP_TYPE= $NETFLOW_UDP_TYPE"
echo "  IPFIX_UDP_TYPE  = $IPFIX_UDP_TYPE"
echo "  BEATS_TCP_TYPE  = $BEATS_TCP_TYPE"

create_input() {
  local title="$1" type="$2" port="$3" proto="$4"
  local conf=''

  case "$type" in
    *SyslogUDP*|*syslog*UDP*)
      conf=$(jq -n --arg port "$port" '{bind_address:"0.0.0.0", port: ($port|tonumber), recv_buffer_size: 262144, override_source:"", allow_override_date:true, expand_structured_data:false}')
      ;;
    *SyslogTCP*|*syslog*TCP*)
      conf=$(jq -n --arg port "$port" '{bind_address:"0.0.0.0", port: ($port|tonumber)}')
      ;;
    *GELF*UDP*)
      conf=$(jq -n --arg port "$port" '{bind_address:"0.0.0.0", port: ($port|tonumber), recv_buffer_size: 262144}')
      ;;
    *GELF*TCP*)
      conf=$(jq -n --arg port "$port" '{bind_address:"0.0.0.0", port: ($port|tonumber)}')
      ;;
    *NetFlow*UDP*)
      conf=$(jq -n --arg port "$port" '{bind_address:"0.0.0.0", port: ($port|tonumber), recv_buffer_size: 10485760, number_worker_threads: 4}')
      ;;
    *IPFIX*UDP*)
      conf=$(jq -n --arg port "$port" '{bind_address:"0.0.0.0", port: ($port|tonumber), recv_buffer_size: 10485760, number_worker_threads: 4}')
      ;;
    *Beats*)
      conf=$(jq -n --arg port "$port" '{bind_address:"0.0.0.0", port: ($port|tonumber)}')
      ;;
    *Raw*UDP*)
      conf=$(jq -n --arg port "$port" '{bind_address:"0.0.0.0", port: ($port|tonumber)}')
      ;;
    *)
      echo "[!] Unsupported type pattern: $type" >&2
      return 1
  esac

  echo "[*] Creating input: $title on $proto/$port ($type)"
  curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json'     -d "$(jq -n --arg t "$title" --arg type "$type" --argjson c "$conf"       '{title:$t, type:$type, global:true, configuration:$c}')"     "${API}/system/inputs" >/dev/null
}

source .env

# Create core inputs
[[ -n "$SYSLOG_UDP_TYPE" ]] && create_input "SYSLOG-UDP-${SYSLOG_UDP_PORT}" "$SYSLOG_UDP_TYPE" "$SYSLOG_UDP_PORT" "udp" || true
[[ -n "$SYSLOG_TCP_TYPE" ]] && create_input "SYSLOG-TCP-${SYSLOG_TCP_PORT}" "$SYSLOG_TCP_TYPE" "$SYSLOG_TCP_PORT" "tcp" || true
[[ -n "$GELF_UDP_TYPE"   ]] && create_input "GELF-UDP-${GELF_UDP_PORT}"   "$GELF_UDP_TYPE"   "$GELF_UDP_PORT"   "udp" || true
[[ -n "$GELF_TCP_TYPE"   ]] && create_input "GELF-TCP-${GELF_TCP_PORT}"   "$GELF_TCP_TYPE"   "$GELF_TCP_PORT"   "tcp" || true
[[ -n "$NETFLOW_UDP_TYPE"]] && create_input "NETFLOW-UDP-${NETFLOW_PORT}" "$NETFLOW_UDP_TYPE" "$NETFLOW_PORT" "udp" || true
[[ -n "$IPFIX_UDP_TYPE"  ]] && create_input "IPFIX-UDP-${IPFIX_PORT}"     "$IPFIX_UDP_TYPE"   "$IPFIX_PORT"   "udp" || true
[[ -n "$BEATS_TCP_TYPE"  ]] && create_input "BEATS-TCP-${BEATS_PORT}"     "$BEATS_TCP_TYPE"   "$BEATS_PORT"     "tcp" || true

echo "[*] Creating index sets, streams, and pipeline rules ..."
# Create a simple index set for 'isp-logs' with 20GB rotation and 90-day retention.
INDEX_ID=$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json' -d '{
  "title":"ISP Logs",
  "description":"Unified logs for NetFlow/NAT/DNS/Radius",
  "index_prefix":"isplogs",
  "shards":1,
  "replicas":0,
  "rotation_strategy_class":"org.graylog2.indexer.rotation.strategies.SizeBasedRotationStrategy",
  "rotation_strategy":{"type":"org.graylog2.indexer.rotation.strategies.SizeBasedRotationStrategyConfig","max_size":20480},
  "retention_strategy_class":"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy",
  "retention_strategy":{"type":"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig","max_number_of_indices":120},
  "writable":true,
  "index_analyzer":"standard",
  "field_type_refresh_interval":5000
}' "${API}/system/indices/index_sets" | jq -r '.id')

# Default stream for isp logs
STREAM_ID=$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json' -d "$(jq -n --arg idx "$INDEX_ID" '{
  "title":"ISP Unified Logs",
  "description":"All ISP log events",
  "index_set_id":$idx,
  "matching_type":"AND",
  "remove_matches_from_default_stream":true
}')" "${API}/streams" | jq -r '.stream.id')

# Start the stream
curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -X POST "${API}/streams/${STREAM_ID}/resume" >/dev/null || true

# Attach pipeline to the stream
PIPELINE_ID=$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json' -d @graylog/pipelines/mikrotik_nat_pipeline.json "${API}/system/pipelines/pipeline" | jq -r '.id')
RULE_ID=$(curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json' -d @graylog/pipelines/mikrotik_nat_rule.json "${API}/system/pipelines/rule" | jq -r '.id')
# Connect rule to pipeline
curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json' -d @graylog/pipelines/mikrotik_stage_connection.json "${API}/system/pipelines/connections/to_stream" >/dev/null

echo "[*] Creating saved searches & dashboards ..."
curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json' -d @graylog/dashboards/saved_searches.json "${API}/views/search" >/dev/null || true
curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" -H 'Content-Type: application/json' -d @graylog/dashboards/maestro_like_dashboard.json "${API}/views" >/dev/null || true

echo "[*] Provisioning complete!"
echo "    - Streams/Index: ISP Unified Logs -> isplogs-*"
echo "    - Inputs: Syslog, GELF, NetFlow/IPFIX, Beats (as available)"
echo "    - Dashboard: Maestro-like Activity/Search"
