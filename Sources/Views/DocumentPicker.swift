import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct DocumentPicker: UIViewControllerRepresentable {
    public let onFilePicked: (URL) -> Void
    public let onCancel: () -> Void
    
    public init(
        onFilePicked: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onFilePicked = onFilePicked
        self.onCancel = onCancel
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .formSheet
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(parent: DocumentPicker) {
            self.parent = parent
        }
        
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let selectedURL = urls.first else { return }
            
            let isAccessing = selectedURL.startAccessingSecurityScopedResource()
            parent.onFilePicked(selectedURL)
            if isAccessing {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }
        
        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
