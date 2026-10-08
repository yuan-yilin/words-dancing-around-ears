import PDFKit
import SwiftUI

/// 跨平台 PDFKit 视图封装
struct PDFKitViewRepresentable: View {
    let document: PDFDocument?

    var body: some View {
        #if os(macOS)
        PDFViewRepresentableNS(document: document)
            .frame(minWidth: 300, minHeight: 400)
        #else
        PDFViewRepresentableUI(document: document)
        #endif
    }
}

#if os(macOS)
private struct PDFViewRepresentableNS: NSViewRepresentable {
    let document: PDFDocument?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
    }
}
#else
import UIKit

private struct PDFViewRepresentableUI: UIViewRepresentable {
    let document: PDFDocument?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
    }
}
#endif
