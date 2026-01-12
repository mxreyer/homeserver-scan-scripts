# Scan scripts

## `scan.sh` 

The script pulls scan(s) from a network scanner, using ADF (simplex/duplex
mode) or flatbed scanner (combines multiple individual scans).  Optionally, it
puts the scan into the paperless consume dir for automatic ingestion.

### Preparation

Adapt the env vars under "Configuration" (find names of network scanners via "airscan -L")

### Usage

- Execute via `scan.sh [options]`, where `options` are
    - `-s`: Simplex scan. Uses ADF to scan a stack of documents.
    - `-d`: Duplex scan. Uses ADF to first scan front pages, then back pages of a stack of documents. Combines them into final pdf. 
    - `-f`: Flatbed scan. Multiple documents can be scanned, they are combined into single pdf.
    - `-p`: Put scan into paperless consume dir.
- If options are not specified, the script walks the user through a series of prompts.

### Notes

- There may be different device names for the same physical device.
    - These may have different options (`airscan -h -d <devicename>`), which may cause issues in the script's usage of `scanimage`. Fix as needed.
    - The scan areas (max width/heights) may differ
- For example, I get for the same Brother MFC-L2710DW printer/scanner:
    - `escl:http://192.168.1.65:80` (fastest, captures document area most reliably)
    - `brother4:net1;dev0`
    - `airscan:e0:Brother MFC-L2710DW series`
