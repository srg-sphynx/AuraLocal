//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import Foundation
import PDFKit
import Vision
import CoreGraphics

/// PDF → Markdown. Each page becomes a `## Page N` section so citations can point at
/// a page and the chunker keeps page boundaries. When a page yields no text (a
/// scanned image) and `ocrFallback` is enabled, the page is rasterized and run
/// through Vision OCR.
enum PDFExtractor {
    static func extract(_ file: ScannedFile, fallbackTitle: String, ocrFallback: Bool) -> ExtractedDocument? {
        guard let doc = PDFDocument(url: file.url) else { return nil }

        var out = ""
        var warnings: [String] = []
        var ocrPages = 0
        var emptyPages = 0

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            var pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if pageText.isEmpty {
                if ocrFallback, let ocr = ocrText(from: page), !ocr.isEmpty {
                    pageText = ocr; ocrPages += 1
                } else {
                    emptyPages += 1
                }
            }
            if !pageText.isEmpty {
                out += "\n\n## Page \(i + 1)\n\n" + pageText + "\n"
            }
        }

        let title = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if ocrPages > 0 { warnings.append("OCR recovered text on \(ocrPages) scanned page(s).") }
        if emptyPages > 0 {
            warnings.append(ocrFallback
                ? "\(emptyPages) page(s) had no recoverable text."
                : "\(emptyPages) page(s) appear scanned — enable PDF OCR in Settings to index them.")
        }

        let md = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if md.isEmpty { warnings.append("No extractable text in PDF.") }
        return ExtractedDocument(markdown: md,
                                 title: (title?.isEmpty == false) ? title : fallbackTitle,
                                 warnings: warnings)
    }

    // MARK: - OCR

    private static func ocrText(from page: PDFPage) -> String? {
        guard let cg = rasterize(page) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        } catch {
            Log.ingest.warning("OCR failed on a PDF page: \(error.localizedDescription)")
            return nil
        }
    }

    private static func rasterize(_ page: PDFPage, scale: CGFloat = 2.0) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}
