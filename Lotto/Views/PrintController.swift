// PrintController.swift
// Lotto
//
// SwiftUI wrapper for UIPrintInteractionController to print a SwiftUI View

import SwiftUI
import UIKit

/// SwiftUI wrapper that renders content to one or more pages.
struct PrintController<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let title: String?
    let date: Date?
    let completion: (() -> Void)?
    
    /// Creates a host controller used to present the print sheet.
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            printView(from: controller)
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    /// Renders the content to images and sends them to the printer.
    private func printView(from controller: UIViewController) {
        let pageSize = CGSize(width: 595, height: 842) // A4-size points
        let margin: CGFloat = 24
        let headerHeight: CGFloat = 36
        let footerHeight: CGFloat = 28
        let printableHeight = pageSize.height - (margin * 2) - headerHeight - footerHeight
        let printableRect = CGRect(
            x: margin,
            y: margin + headerHeight,
            width: pageSize.width - (margin * 2),
            height: printableHeight
        )

        let rootView = content
            .frame(width: printableRect.width)
            .padding()
            .background(Color.white)
        let headerText = formattedHeader()
        let screenScale = controller.view.window?.windowScene?.screen.scale
            ?? controller.traitCollection.displayScale
        let fullImage = renderContentImage(
            view: rootView,
            width: printableRect.width,
            scale: screenScale
        )
        let images = sliceAndComposePages(
            fullImage: fullImage,
            pageSize: pageSize,
            printableRect: printableRect,
            headerText: headerText,
            headerHeight: headerHeight,
            footerHeight: footerHeight,
            margin: margin
        )

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = title ?? "Lotto Resultater"

        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        printController.printingItems = images

        printController.present(from: controller.view.frame, in: controller.view, animated: true) { _, _, _ in
            completion?()
        }
    }

    /// Builds the header text with title and optional date.
    private func formattedHeader() -> String {
        guard let title else {
            return ""
        }
        guard let date else {
            return title
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(title) – \(formatter.string(from: date))"
    }

    private func renderContentImage(view: some View, width: CGFloat, scale: CGFloat) -> UIImage {
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = .init(width: width, height: nil)
            renderer.scale = scale
            if let image = renderer.uiImage {
                return image
            }
        }

        let fallback = UIHostingController(rootView: view)
        fallback.view.backgroundColor = UIColor.white
        let targetSize = CGSize(width: width, height: 10000)
        fallback.view.frame = CGRect(origin: .zero, size: targetSize)
        fallback.view.setNeedsLayout()
        fallback.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: fallback.view.bounds.size)
        return renderer.image { context in
            fallback.view.layer.render(in: context.cgContext)
        }
    }

    private func sliceAndComposePages(
        fullImage: UIImage,
        pageSize: CGSize,
        printableRect: CGRect,
        headerText: String,
        headerHeight: CGFloat,
        footerHeight: CGFloat,
        margin: CGFloat
    ) -> [UIImage] {
        guard let cgImage = fullImage.cgImage else {
            return []
        }

        let scale = fullImage.scale
        let contentHeightPoints = fullImage.size.height
        let contentRemainder = contentHeightPoints.truncatingRemainder(dividingBy: printableRect.height)
        let minimumVisibleSliceHeight: CGFloat = 18
        var pageCount = max(1, Int(ceil(contentHeightPoints / printableRect.height)))
        if pageCount > 1, contentRemainder > 0, contentRemainder < minimumVisibleSliceHeight {
            pageCount -= 1
        }
        let renderer = UIGraphicsImageRenderer(size: pageSize)
        var images: [UIImage] = []
        images.reserveCapacity(pageCount)

        let contentWidthPixels = CGFloat(cgImage.width)
        let sliceHeightPixels = printableRect.height * scale

        for pageIndex in 0..<pageCount {
            let originY = CGFloat(pageIndex) * sliceHeightPixels
            let height = min(sliceHeightPixels, CGFloat(cgImage.height) - originY)
            let cropRect = CGRect(x: 0, y: originY, width: contentWidthPixels, height: height)
            guard let sliceCg = cgImage.cropping(to: cropRect) else { continue }
            let slice = UIImage(cgImage: sliceCg, scale: scale, orientation: .up)

            let pageImage = renderer.image { context in
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fill(CGRect(origin: .zero, size: pageSize))

                let headerRect = CGRect(
                    x: margin,
                    y: margin,
                    width: pageSize.width - (margin * 2),
                    height: headerHeight
                )
                if !headerText.isEmpty {
                    let headerAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 12.6),
                        .foregroundColor: UIColor.black
                    ]
                    NSString(string: headerText).draw(in: headerRect, withAttributes: headerAttrs)
                }

                let footerText = "Page \(pageIndex + 1) of \(pageCount)"
                let footerRect = CGRect(
                    x: margin,
                    y: pageSize.height - margin - footerHeight,
                    width: pageSize.width - (margin * 2),
                    height: footerHeight
                )
                let footerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10.8),
                    .foregroundColor: UIColor.darkGray
                ]
                NSString(string: footerText).draw(in: footerRect, withAttributes: footerAttrs)

                // Keep the final partial slice at its natural height to avoid vertical stretching.
                let drawRect = CGRect(
                    x: printableRect.minX,
                    y: printableRect.minY,
                    width: printableRect.width,
                    height: min(printableRect.height, slice.size.height)
                )
                slice.draw(in: drawRect)
            }
            images.append(pageImage)
        }

        return images
    }
}
