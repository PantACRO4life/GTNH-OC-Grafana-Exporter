
# Download
After installing OpenOS and rebooting, run this command to download the program:

# Exporter
```wget -f https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/exporter.lua```


# Git Puller and script for main server/Updater
```wget -f https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/OC-NAS/git_pull.lua ; wget -f https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/OC-NAS/nas_server_push_chunked.lua ; wget -f https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/OC-NAS/.shrc_server /home/.shrc```

run ```git_pull``` command once downloaded to pull all the configs and exporter on the main server.

# Updater installation  for clients 
Hostname of client:  pc must be [items001 or higher, fluids001 or higher, essentia001 or higher, energy001 or higher, multi001 or higher, cpus001 or higher) to correctly send their status and requirement on the main server.

command to pull stuff on client and auto start it
```wget -f https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/OC-NAS/nas_client_sync.lua ; wget -f https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/OC-NAS/.shrc_client /home/.shrc; reboot```

(use middle click to paste). You'll then need to edit the config, but we'll come back to that after setting up InfluxDB and Grafana.

