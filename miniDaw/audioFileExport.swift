//
//  audioFileExport.swift
//  miniDaw
//
//  Created by Artur Makoev on 17.07.2026.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct AudioFileDocument: FileDocument {
    // Define the types of files this document can read/write
    static var readableContentTypes: [UTType] { [.wav, .audio] }

    var tempFileURL: URL?

    // Initialize an empty document
    init(tempFileURL: URL? = nil) {
        self.tempFileURL = tempFileURL
    }

    // Required initializer to load existing files (can be empty for export-only)
    init(configuration: ReadConfiguration) throws {
        self.tempFileURL = nil
    }

    // This is called when the file exporter writes the file to the user's chosen destination
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let tempFileURL = tempFileURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        // Read the data from our temporary bounced file and wrap it
        let data = try Data(contentsOf: tempFileURL)
        return FileWrapper(regularFileWithContents: data)
    }
}
