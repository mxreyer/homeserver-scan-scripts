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

# Parse arguments
SCANTYPE=""
PAPERLESS=""
EXP_PAGES=-1
BREAK_PAGES=-1
while getopts "sdfpn:b:" opt; do
    case "$opt" in
	s) SCANTYPE="simplex" ;;
	d) SCANTYPE="duplex" ;;
	f) SCANTYPE="flatbed" ;;
        p) PAPERLESS="yes" ;;
        n) EXP_PAGES=$OPTARG ;;
        b) BREAK_PAGES=$OPTARG ;;
    esac
done

# Check input
if ! [[ $EXP_PAGES =~ ^[0-9]+$ ]]; then
  echo "the argument for flag -n must be a number!"
  exit 1;
fi

# Configuration
OUTPUT_DIR="$HOME/scans"
BASENAME="scan_$(date +%Y%m%d_%H%M%S)"
TMP_FINAL_PDF="${tmpdir}/${BASENAME}.pdf"
FINAL_PDF="${OUTPUT_DIR}/${BASENAME}.pdf"
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

get_pdf_pages() {
    #pdftk "$1" dump_data | grep NumberOfPages | awk '{print $2}'
    pdfinfo "$1" | awk '/Pages:/ {print $2}'
}

scan_adf_pdf() {
    local outfile="$1"

    scanimage \
        ${DEVICE:+--device-name "$DEVICE"} \
        --source "Automatic Document Feeder(left aligned)" \
        --resolution "$RESOLUTION" \
        --format=pdf \
        --batch="$outfile" --batch-print
    
    pages=$(get_pdf_pages "$outfile")
}

scan_adf_pdf_wrapper() {
    local outfile="$1"
    
    while true; do
        wait_for_button
        echo "Scanning pages..."
        scan_adf_pdf "$outfile"
        if (( pages == EXP_PAGES )); then
            echo "✅ Scanned $pages pages."
            break
        else
            echo "⚠️ Warning: Expected page count not matched (${pages} vs. ${EXP_PAGES})."
            echo "➡️ Repeat scan now."
            echo ""
        fi
    done
}

break_pdf_pages()  {
  local infile="$1"
  local totpages=$(get_pdf_pages "$infile")
  outfiles=()

  for i in $(seq 1 ${BREAK_PAGES} $totpages); do 
      # create range for pdftk
      startpage=$i
      endpage=$((i+BREAK_PAGES-1))
  
      # handle situation that total pages is not a multiple of BREAK_PAGES
      if (( endpage > totpages )); then
  	echo
  	echo "⚠️ Warning: PDF pages are not m multiple of ${BREAK_PAGES}. Last PDF will be shorter."
          endpage=$totpages;
      fi 
  
      # run pdftk
      output="${infile%.pdf}-${startpage}-${endpage}.pdf"
      outfiles+=("$output")
      pdftk $infile cat $startpage-$endpage output $output

  done
  
  echo "✅ Split into ${#outfiles[@]} files." 

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

# Ask duplex vs simplex
[[ -z "$SCANTYPE" ]] && ask_scan_type

# Simplex workflow
if [[ "$SCANTYPE" == "simplex" ]]; then
    wait_for_button
    echo "Scanning simplex document..."
    scan_adf_pdf "$TMP_FINAL_PDF"
    echo "✅ Simplex scan complete: $TMP_FINAL_PDF"
fi

# Duplex workflow
if [[ "$SCANTYPE" == "duplex" ]]; then
    ODD_PDF="${tmpdir}/odd.pdf"
    EVEN_PDF="${tmpdir}/even.pdf"
    
    echo "Load documents for ODD pages."
    scan_adf_pdf_wrapper "$ODD_PDF"
    pagesodd=$pages

    echo
    echo "Now reinsert pages for EVEN pages (flip stack upside down)."
    scan_adf_pdf_wrapper "$EVEN_PDF"
    pageseven=$pages

    if (( pagesodd != pageseven )); then
	echo
	echo "⚠️ Warning: Odd and even page counts do not match (${pagesodd} vs. ${pageseven})! This may be an ADF issue."
    fi

    echo
    echo "Merging odd and even pages..."
    
    pdftk \
        A="$ODD_PDF" \
        B="$EVEN_PDF" \
        shuffle A Bend-1 \
        output "$TMP_FINAL_PDF"
    
    echo "✅ Duplex scan complete: $TMP_FINAL_PDF"
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
        output "$TMP_FINAL_PDF"

    echo "✅ Flatbed scan complete: $TMP_FINAL_PDF"
fi

# Break final pdf into chunks
if (( BREAK_PAGES > 0 )); then
  echo ""
  echo "Splitting PDF up..."
  break_pdf_pages "$TMP_FINAL_PDF"
  FINAL_PDF_FILES=()
  for f in "${outfiles[@]}"; do
    newf="${OUTPUT_DIR}/${f##*/}"
    mv "$f" "$newf"
    FINAL_PDF_FILES+=("$newf")
  done
else
  mv "$TMP_FINAL_PDF" "$FINAL_PDF"
  FINAL_PDF_FILES=("$FINAL_PDF")
fi

echo ""
echo "🏁 Final file(s): ${FINAL_PDF_FILES[@]}"

# Push to paperless consume dir
echo ""
[[ -z "$PAPERLESS" ]] && ask_paperless
if [[ "$PAPERLESS" == "yes" ]]; then
    mv "${FINAL_PDF_FILES[@]}" "$PAPERLESS_CONSUME_DIR"
    echo "💾 Moved file(s) to $PAPERLESS_CONSUME_DIR"
fi
