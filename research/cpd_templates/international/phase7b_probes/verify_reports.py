"""Inspect the extracted text, page bodies, annotations and copy fidelity.

Run with the PDFium and pypdf tooling against the synthetic artifact directory.
A shaped report can pass visual and search checks while still failing exact copy.
"""
import argparse
import json
import re
import unicodedata
from pathlib import Path

import pypdfium2 as pdfium
from pypdf import PdfReader


HINDI_PHRASES = (
    "शिक्षा और व्यावसायिक प्रशिक्षण",
    "हिन्दी में चिकित्सा क्षेत्र",
    "प्रशिक्षण पूरा हुआ।",
)
METADATA_LABELS = ("Template version", "Reporting rules", "Regulatory review")
LINK = "https://example.com/resources/learning-log"
LONG_LINK = "https://example.com/evidence/long-path/" + "".join(
    f"PATH{i:03d}" for i in range(92)
)


def flat(text):
    return "".join(unicodedata.normalize("NFC", text).split())


def inspect(path, phrases=()):
    copied = {phrase: [] for phrase in phrases}
    pages = []
    with pdfium.PdfDocument(str(path)) as document:
        for index, page in enumerate(document, start=1):
            textpage = page.get_textpage()
            raw = textpage.get_text_range()
            body = re.sub(
                r"CPD Progress Tracker(?:\s*·\s*Synthetic example)?"
                r"|Page\s+\d+\s+of\s+\d+",
                "",
                raw,
                flags=re.IGNORECASE,
            ).strip()
            assert body, f"Blank or footer-only page {index} in {path.name}"
            pages.append(raw)
            for phrase in phrases:
                search = textpage.search(phrase)
                while (hit := search.get_next()) is not None:
                    copied[phrase].append(textpage.get_text_range(*hit))
                search.close()
            textpage.close()
            page.close()
    return pages, copied


def links(path):
    return {
        uri
        for page in PdfReader(path).pages
        for ref in page.get("/Annots", ())
        if (uri := ref.get_object().get("/A", {}).get("/URI"))
    }


def verify(root):
    western = root / "stress-western.pdf"
    pages, _ = inspect(western)
    joined = flat(" ".join(pages))
    for i in range(360):
        assert joined.count(f"Recordintegritymarker{i:04d}.") == 1, i
    assert "".join(f"REF{i:03d}" for i in range(120)) in joined
    assert LONG_LINK in joined
    assert "Preservedhistoricalsupervisorvalue" in joined
    assert "EXCLUDEDTESTVALUE" not in joined
    assert "Finaloriginaltext·Revisiónterminada·Prüfungabgeschlossen." in joined
    for number in (0, 2, 4):
        for line in range(1, 69):
            assert f"Observation{number:04d}-{line}." in joined
    assert "continued" in joined
    assert links(western) == {LINK, LONG_LINK}

    boundaries = {}
    for index, n in enumerate((1, 38, 67, 121)):
        path = root / f"boundary-{index}.pdf"
        body, _ = inspect(path)
        boundaries[str(n)] = len(body)
        assert all(f"Bodyparagraph{i}." in flat("".join(body)) for i in range(1, n + 1))
        assert "Boundaryend" in flat("".join(body))
        assert links(path) == {LINK}
    recipient, _ = inspect(root / "nmc-recipient.pdf")
    assert all(label not in " ".join(recipient) for label in METADATA_LABELS)
    return {"westernPages": len(pages), "boundaryPages": boundaries}


def shape(path):
    pages, copied = inspect(path, HINDI_PHRASES)
    body = flat(" ".join(pages))
    return {
        "name": path.name,
        "pages": len(pages),
        "bytes": path.stat().st_size,
        "lastNumberedParagraphs": body.count("अवलोकन85·"),
        "searchHits": {phrase: len(hits) for phrase, hits in copied.items()},
        "exactCopies": {
            phrase: sum(text == phrase for text in hits)
            for phrase, hits in copied.items()
        },
        "allNumberedParagraphs": all(
            body.count(f"अवलोकन{i}·") == 2 for i in range(1, 86)
        ),
        "allNamedLinks": links(path) == {LINK, LONG_LINK},
        "hasActualText": any(
            b"/ActualText" in page.get_contents().get_data()
            for page in PdfReader(path).pages
        ),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("shape", type=Path, nargs="*")
    args = parser.parse_args()
    print(json.dumps(
        {"reportRegression": verify(args.directory), "shaping": [shape(path) for path in args.shape]},
        ensure_ascii=False,
        indent=2,
    ))
