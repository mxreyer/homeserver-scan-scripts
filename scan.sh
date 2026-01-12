#!/bin/bash
# ==============================================================================
# Script Name: scan.sh
# Description: Scan documents from network scanner
#
# Usage: ./scan.sh [options], then follow promts
# ==============================================================================

set -euo pipefail # exit on error, undef vars, or failed pipeline
set -o errtrace   # inherit ERR trap by functions, command subs, subshells 

tmpdir=$(mktemp -d)

on_exit() {
    rm -r "$tmpdir"
}
trap on_exit EXIT

on_error() {
    echo "❌ Scan failed."
}
trap on_error ERR

# === Parse arguments ==
SCANTYPE=""
PAPERLESS=""
while getopts "sdfp" opt; do
    case "$opt" in
	s) SCANTYPE="simplex" ;;
	d) SCANTYPE="duplex" ;;
	f) SCANTYPE="flatbed" ;;
        p) PAPERLESS="yes" ;;
    esac
done

# Configuration
OUTPUT_DIR="$HOME/scans"
BASENAME="scan_$(date +%Y%m%d_%H%M%S)"
FINAL_PDF="$OUTPUT_DIR/${BASENAME}.pdf"
PAPERLESS_CONSUME_DIR=/home/max/docker-binds/paperless/consume
RESOLUTION=300
DEVICE="escl:http://192.168.1.65:80" # leave empty for default scanner, or set device name (airscan -L)

mkdir -p "$OUTPUT_DIR"

ask_scan_type() {
    read -rp "Specify scan type (s[implex]/d[uplex]/f[latbed]): " scantype
    case "$scantype" in
        s|simplex) SCANTYPE="simplex" ;;
        d|duplex)  SCANTYPE="duplex" ;;
        f|flatbed) SCANTYPE="flatbed" ;;
        *) echo "Invalid answer"; exit 1 ;;
    esac
}

ask_paperless() {
read -rp "Move scan to paperless consume dir (${PAPERLESS_CONSUME_DIR})? (y/n): " paperless
    case "$paperless" in
        y|Y) PAPERLESS=yes ;;
        n|N) PAPERLESS=no ;;
        *) echo "Invalid answer"; exit 1 ;;
    esac
}

wait_for_button() {
    echo "Press any key to start scanning..."
    read -n 1 -s
    echo
}

PRESSED_KEY=""
wait_for_button_exit() {
    echo "Press any key to start scanning... (or s to stop scan)"
    read -n 1 PRESSED_KEY
    echo
}

scan_adf_pdf() {
    local outfile="$1"

    scanimage \
        ${DEVICE:+--device-name "$DEVICE"} \
        --source "Automatic Document Feeder(left aligned)" \
        --resolution "$RESOLUTION" \
        --format=pdf \
        --batch="$outfile" --batch-print
}

scan_flatbed_pdf() {
    local outfile="$1"

    scanimage \
        ${DEVICE:+--device-name "$DEVICE"} \
        --source "FlatBed" \
        --resolution "$RESOLUTION" \
        --format=pdf \
        > "$outfile"
}

#ask_duplex
[[ -z "$SCANTYPE" ]] && ask_scan_type

# Simplex workflow
if [[ "$SCANTYPE" == "simplex" ]]; then
    wait_for_button
    echo "Scanning simplex document..."
    scan_adf_pdf "$FINAL_PDF"
    echo "✅ Simplex scan complete: $FINAL_PDF"
fi

# Duplex workflow
if [[ "$SCANTYPE" == "duplex" ]]; then
    ODD_PDF="${tmpdir}/odd.pdf"
    EVEN_PDF="${tmpdir}/even.pdf"
    
    echo "Load documents for ODD pages."
    wait_for_button
    echo "Scanning odd pages..."
    scan_adf_pdf "$ODD_PDF"
    
    echo
    echo "Now reinsert pages for EVEN pages (typically flipped)."
    wait_for_button
    echo "Scanning even pages..."
    scan_adf_pdf "$EVEN_PDF"

    pagesodd=$(pdfinfo ${ODD_PDF}  | awk '/Pages:/ {print $2}')
    pageseven=$(pdfinfo ${EVEN_PDF} | awk '/Pages:/ {print $2}')
    if (( pagesodd != pageseven )); then
	echo
	echo "⚠️ Warning: Odd and even page counts do not match (${pagesodd} vs. ${pageseven})! ADF issue?"
    fi

    echo
    echo "Merging odd and even pages..."
    
    pdftk \
        A="$ODD_PDF" \
        B="$EVEN_PDF" \
        shuffle A Bend-1 \
        output "$FINAL_PDF"
    
    echo "✅ Duplex scan complete: $FINAL_PDF"
fi

# Flatbed workflow
if [[ "$SCANTYPE" == "flatbed" ]]; then

    PDF_PAGES=""

    echo "Place document on flatbed scanner."
    wait_for_button
    
    KEY=""
    NUM=1
    while [[ "$PRESSED_KEY" != "s" ]]; do
	PDF_PAGE="${tmpdir}/${NUM}.pdf"
        echo "Scanning page..."
        scan_flatbed_pdf "$PDF_PAGE"
	PDF_PAGES="$PDF_PAGES $PDF_PAGE"
    	echo "Place document on flatbed scanner."
	wait_for_button_exit
	NUM=$((NUM+1))
    done
    
    echo
    echo "Merging individual pages... (${PDF_PAGES})"

    pdftk \
	$PDF_PAGES \
        cat \
        output "$FINAL_PDF"

    echo "✅ Flatbed scan complete: $FINAL_PDF"
fi

[[ -z "$PAPERLESS" ]] && ask_paperless

# Push to paperless consume dir
if [[ "$PAPERLESS" == "yes" ]]; then
    mv "$FINAL_PDF" "$PAPERLESS_CONSUME_DIR"
    echo "💾 Moved $FINAL_PDF to $PAPERLESS_CONSUME_DIR"
fi
