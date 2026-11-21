import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - 相机

/// 系统相机（UIImagePickerController 的 SwiftUI 包装）。只拍照片，不录视频。
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPick(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

// MARK: - 临时文件（发送前暂存）

/// 暂存文件：只在“选完、还没发”这段时间用。点发送时，
/// AttachmentStaging.persistSentMedia 会把它们拷到持久目录
/// Application Support/Attachments/，tmp 里的原文件不再被引用。
/// nonisolated：照片选择器的 Transferable 回调不在 MainActor 上，
/// 也要能调它们。
nonisolated func tempFileURL(fileName: String) -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString + "-" + fileName)
}

nonisolated func writeTempFile(data: Data, fileName: String) throws -> URL {
    let url = tempFileURL(fileName: fileName)
    try data.write(to: url, options: .atomic)
    return url
}

// MARK: - 选到的东西变成附件

/// 视频的 Transferable：只拿文件地址，不把整段视频读进内存。
struct MovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = tempFileURL(fileName: "video.mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

/// 照片选择器里选出来的东西（照片和视频）变成附件。
/// 照片按实际格式存：HEIC 的照片存成 .heic，绝不写成 .jpg
/// （扩展名从选择器给的 content type 里拿）。
/// 返回没能加进来的张数，调用方要告诉用户，不许悄悄丢。
func mediaFromPhotoItems(_ items: [PhotosPickerItem]) async -> (media: [MediaAttachment], failedCount: Int) {
    var media: [MediaAttachment] = []
    var failed = 0
    for item in items {
        let types = item.supportedContentTypes
        let isVideo = types.contains {
            $0.conforms(to: .audiovisualContent) && !$0.conforms(to: .image)
        }
        if isVideo {
            if let movie = try? await item.loadTransferable(type: MovieTransferable.self) {
                media.append(await mediaFromVideoURL(movie.url))
            } else {
                failed += 1
            }
        } else if let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) {
            let ext = types.first(where: { $0.conforms(to: .image) })?.preferredFilenameExtension ?? "jpg"
            if let url = try? writeTempFile(data: data, fileName: "photo.\(ext)") {
                media.append(.image(url: url, width: image.cgImage?.width, height: image.cgImage?.height))
            } else {
                failed += 1
            }
        } else {
            failed += 1
        }
    }
    return (media, failed)
}

func mediaFromVideoURL(_ url: URL) async -> MediaAttachment {
    let asset = AVAsset(url: url)
    var duration: TimeInterval? = nil
    if let d = try? await asset.load(.duration) {
        duration = d.seconds
    }
    var thumbURL: URL? = nil
    do {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        if let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) {
            thumbURL = try? writeTempFile(data: data, fileName: "thumb.jpg")
        }
    } catch {
        // 缩略图拿不到就不要，气泡自己会处理。
    }
    return .video(url: url, thumbnailURL: thumbURL, duration: duration)
}

/// 文件选择器里选出来的文件变成附件（先拷一份到咱们的地盘，
/// 系统给的地址离开选择器就失效了）。
/// 用 NSFileCoordinator 协调着读：iCloud 还没下载完、QQ/微信等
/// 第三方来源的文件，协调读比直接拷更稳；拷不动的记进 failedNames，
/// 调用方要给用户一句明确提示，绝不悄悄丢。
func mediaFromFileURLs(_ urls: [URL]) -> (media: [MediaAttachment], failedNames: [String]) {
    var media: [MediaAttachment] = []
    var failed: [String] = []
    for url in urls {
        let name = url.lastPathComponent
        guard url.startAccessingSecurityScopedResource() else {
            failed.append(name)
            continue
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let destination = tempFileURL(fileName: name)
        var copyError: NSError?
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &copyError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: destination)
                copied = true
            } catch {
                copied = false
            }
        }
        guard copied, copyError == nil else {
            failed.append(name)
            continue
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value
        media.append(.file(url: destination, name: name, size: size))
    }
    return (media, failed)
}

func mediaFromCameraImage(_ image: UIImage) -> MediaAttachment? {
    guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
    guard let url = try? writeTempFile(data: data, fileName: "camera.jpg") else { return nil }
    return .image(url: url, width: image.cgImage?.width, height: image.cgImage?.height)
}
