#!/bin/python3
# ==============================================================================
# Script Name: check-text-orientation.py 
# Description: Runs OCR on all 4 rotations for each page of the input PDF to
#              determine the text orientation. The script rotates the page accordingly. If
#              more that one text orientation is found, the script inserts copies for all
#              valid rotations. This is done so that paperless ngx properly identifies all
#              kinds of text in the document.
#
# Usage: ./check-text-orientation.py [options]
# ==============================================================================

from pypdf import PdfReader, PdfWriter, PageObject
from pdf2image import convert_from_path
from optparse import OptionParser
import pytesseract
import tempfile
import os
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# option parser
parser = OptionParser(usage="usage: %prog [options]\n Checks for pages with vertical text and inserts rotated versions for proper OCR recognition.")
parser.add_option("-o", dest="output", default="output.pdf",
                  help="output pdf file",
                  metavar="FILE")
parser.add_option("-i", dest="input", default="input.pdf",
                  help="input pdf file",
                  metavar="FILE")
parser.add_option("--ocr-dpi", dest="ocr_dpi", default=300,
                  help="dpi for ocr recognition",
                  metavar="INTEGER")
parser.add_option("-l", "--ocr-min-word-len", dest="ocr_min_word_len", default=3,
                  help="minimum character length for a word to classify as good",
                  metavar="INTEGER")
parser.add_option("-t", "--ocr-word-threshold", dest="ocr_word_threshold", default=10,
                  help="page orientation is considered valid if more than this number of good words found",
                  metavar="INTEGER")
parser.add_option("--conf-threshold", dest="ocr_conf_threshold", default=95,
                  help="minimum confidence for a word to classify as good",
                  metavar="INTEGER")
(opt, args) = parser.parse_args()

# find and count high-quality OCR word identifications
def ocr_good_word_count(image, threshold=opt.ocr_conf_threshold):

    # run OCR
    data = pytesseract.image_to_data(
        image,
        output_type=pytesseract.Output.DICT,
        config="--psm 6"
    )

    # filter OCR words by quality criteria
    goodword_dict={w:c for c,w in zip(data["conf"],data["text"])}
    goodword_dict={w:c for w,c in goodword_dict.items() if c != "-1" and int(c) >= threshold}
    goodword_dict={w:c for w,c in goodword_dict.items() if len(w)>=opt.ocr_min_word_len}

    return len(goodword_dict)

# turn pdf into png, rotate, and check if good word count > threshold
def page_has_text_orientation(pdf_path, page_index, rotang=0):
    images = convert_from_path(
        pdf_path,
        dpi=opt.ocr_dpi,
        first_page=page_index + 1,
        last_page=page_index + 1,
    )
    img = images[0]
    rot_img=img.rotate(-rotang, expand=True)

    ocr_wc = ocr_good_word_count(rot_img)
    pass_threshold = ocr_wc > opt.ocr_word_threshold
    print(f"rotated by {rotang:03d}deg: found {ocr_wc:04d} good ocr words ➡️  threshold passed: {pass_threshold}.")

    return pass_threshold

# read pdf, detect text in all 4 horizontal/vertical directions.
def process_pdf(input_pdf, output_pdf):
    reader = PdfReader(input_pdf)
    writer = PdfWriter()
   
    watermark_pdf=SCRIPT_DIR/"watermark.pdf"
    print(f"watermark:{watermark_pdf}")
    watermark_page = PdfReader(watermark_pdf).pages[0]
    watermark_page.scale_to(
        reader.pages[0].mediabox.width,
        reader.pages[0].mediabox.height,
    )

    for i, page in enumerate(reader.pages):
        valid_rotangs = [ rotang for rotang in [0,180,90,270] if page_has_text_orientation(input_pdf, i, rotang=rotang) ]
        if len(valid_rotangs)==0:
            writer.add_page(page)
        else:
            for j, rotang in enumerate(valid_rotangs):
                dup_page = PageObject.create_blank_page(
                    width=page.mediabox.width,
                    height=page.mediabox.height
                )
                dup_page.merge_page(page)  # copy content into a fresh object
                dup_page.rotate(rotang)
                if j > 0:
                    dup_page.merge_page(watermark_page)
                writer.add_page(dup_page)

    with open(output_pdf, "wb") as f:
        writer.write(f)

# main
if __name__ == "__main__":
    process_pdf(opt.input, opt.output)
