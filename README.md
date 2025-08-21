# ISP INTERNET — ISP Activity Log Server (Open Source)

A production-ready, single-node stack to collect and search ISP user activity for ~50,000 users:
- **NetFlow/IPFIX** (flows, bytes/packets, first/last, NAT fields when exported)
- **NAT hit logs** (from MikroTik/Cisco where supported)
- **DNS query logs** (Unbound/dnsdist)
- **PPPoE/DHCP/RADIUS** (map user/MAC ↔ IP addresses)
- **Syslog/GELF/Beats** inputs for anything else

UI & search powered by **Graylog** (Open Source) on **OpenSearch**. You get dashboards and an **Activity Log Search** page similar to Maestro.

---

## Hardware Sizing (50k active users)
- **CPU:** 16–24 cores
- **RAM:** 64–128 GB (OpenSearch heap ~16–32GB; Graylog heap ~8GB)
- **DISK:** NVMe SSD 4–8 TB usable for hot logs (RAID1 or RAID10). Keep the OpenSearch data path on the fastest storage.
- **OS:** Ubuntu 22.04/24.04 LTS or Debian 12

> For longer retention, consider a cold tier (HDD) or ClickHouse/MinIO add‑on. This stack targets *fast search* for the last 90–180 days.

---

## Quick Start

1) **Edit `.env`**
   - Set `GRAYLOG_HTTP_EXTERNAL_URI` to your server URL (e.g., `http://59.153.100.78:9000/`).
   - Change `GL_PASSWORD_SECRET` and (optionally) `GL_ROOT_PW_SHA2` (admin password).

2) **Start**
```bash
cd log-stack
sudo ./scripts/install.sh
```

3) **Provision inputs & dashboards**
```bash
sudo ./scripts/provision.sh
```
Default login: `admin / admin` (change it immediately).

4) **Point devices to the server**
   - **Syslog UDP/TCP:** `:1514`
   - **GELF UDP/TCP:** `:12201`
   - **NetFlow v9:** `:2055`
   - **IPFIX:** `:4739`
   - **Beats (Filebeat):** `:5044`

Use the examples in `device-configs/` for MikroTik, Cisco NCS, dnsdist/Unbound, and FreeRADIUS.

---

## Search Examples (Graylog)

- **Time + User IP:** `preNAT_src_ip:10.1.2.3 AND dst_ip:203.* AND dst_port:443`
- **By NAT IP:** `postNAT_src_ip:59.153.103.* AND dst_domain:"youtube.com"`
- **By MAC:** `mac:"00:11:22:33:44:55"` (from DHCP/RADIUS/PPPoE logs)
- **By Domain:** `dns.qname:"facebook.com"` (from DNS logs)
- **By User (PPPoE):** `user:"017xxxxxxx"`

Saved searches and a Maestro-like dashboard are auto-created by the provision script.

---

## Notes & Best Practices

- **NAT mapping:** Prefer exporters that include NAT fields in NetFlow/IPFIX (e.g., Cisco Flexible NetFlow). MikroTik NAT logging is possible via syslog but very chatty—use carefully.
- **DNS privacy:** Only log from *your* recursive resolvers (Unbound/dnsdist). Don’t decrypt customer DoH.
- **Retention:** Default is rotation by 20GB per index and up to 120 indices (~2.4 TB). Adjust in `scripts/provision.sh` → `max_size`, `max_number_of_indices`.
- **Backups:** Snapshot OpenSearch indices or replicate to a second node. Keep Mongo/Graylog configs backed up.
- **Scaling out:** Add more OpenSearch nodes and point `GRAYLOG_ELASTICSEARCH_HOSTS` to the cluster. Use dedicated flow collectors if FPS exceeds ~10k.

---

## বাংলা (Bangla) — দ্রুত গাইড

**উদ্দেশ্য:** ইউজারের *Time, Source/Destination IP/Port, MAC, Domain* — সবকিছু এক জায়গায় ট্রেস করা।

**স্ট্যাক:** Graylog (UI) + OpenSearch (স্টোরেজ) + MongoDB (মেটা)।  
**ইনপুট:** Syslog, GELF, NetFlow/IPFIX, Beats. DNS/PPPoE/DHCP/Radius লগও পাঠানো যাবে।

### স্টেপস
1. `.env` ফাইল এ সার্ভারের URL দিন, পাসওয়ার্ড সিক্রেট চেঞ্জ করুন।
2. `sudo ./scripts/install.sh`
3. `sudo ./scripts/provision.sh`
4. রাউটার/ডিএনএস/রেডিয়াস কে `device-configs/` থেকে কনফিগ কপি করুন।

### সার্চ ফিল্ড (উদাহরণ)
- `preNAT_src_ip:10.10.5.23 AND dst_port:443`
- `postNAT_src_ip:59.153.103.17 AND dns.qname:"toffeelive.com"`
- `user:"017xxxxxxxx"`
- `mac:"aa:bb:cc:dd:ee:ff"`

### সতর্কতা
- MikroTik NAT log অনেক বেশি ভলিউম তৈরি করে—সীমিত রুলে *log=yes* দিন (শুধু CGNAT pool/Out-interface) এবং আলাদা router action/remote syslog ব্যবহার করুন।
- ডিস্ক অবশ্যই NVMe নিন। `vm.max_map_count=262144` প্রয়োগ করুন (install.sh করে দেয়)।

---

## Troubleshooting

- **Graylog web 504/Unavailable:** Wait 2–3 minutes after first start; check `docker compose logs graylog`.
- **Inputs not created:** Run `./scripts/provision.sh` again. Check `/api/system/inputs/types` to confirm the type names in your Graylog version.
- **High FPS drops:** Reduce sampled flows or deploy dedicated flow collectors; raise `recv_buffer_size` in `provision.sh` for NetFlow/IPFIX inputs.
- **Disk usage high:** Adjust rotation/retention in `provision.sh`; consider cold storage.
