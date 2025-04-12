## Setting up the OC Computer
# Placement
To start, you'll need to make an OC Computer (a server work aswell) with all the required parts, including 
an Internet Card, as well as an EEPROM and Lua BIOS. I don't know what the minimum tiers for most components 
are, and I just did Tier 3 to be safe, but for the memory I know it should work with as little as 256 KB (one Tier 1.5 Memory), 
though you might need to change the config for that. In addition, you'll need a Screen, a Keyboard, an OC Adapter, and an OC 
Power Converter. Plug the Power Converter into power (I believe AE, RF, and EU all work) and place it either adjacent to the 
Computer Case or connected by OC Cable. Place the Adapter adjacent to the LSC controller block and/or an ME Interface (or a Dual Interface) on 
the network you want to export from; you'll need the LSC to export energy data, and the ME Interface to 
export items/fluids/essentia/CPUs. Make sure you don't have any GT machines other than the LSC adjacent to any connected Adapters; cables 
count as GT machines for this. If you don't want to export all of them, you can disable some in the config, which will also remove the 
need to place an Adapter adjacent; you can also use multiple Adapters connected by OC Cable if that's easier. 

# Download
After installing OpenOS and rebooting, run this command to download the program:

```wget https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/exporter.lua ; wget https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/config.lua ; wget https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/friendly_names.csv```

(use middle click to paste). You'll then need to edit the config, but we'll come back to that after setting up InfluxDB and Grafana.

