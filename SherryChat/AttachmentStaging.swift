import Foundation

/// 已发附件持久化：发送前把附件从暂存位置（tmp 或选择器给的安全域地址，
/// 系统随时会清）拷一份到 `Library/Application Support/Attachments/<每次发送
/// 的 UUID>/原文件名`，再把新地址交给 Conversation。拷不动的那一项返回 nil，
/// 调用方必须告诉用户，绝不悄悄把附件丢掉。

// MARK: - 已发附件的持久目录

/// 已发附件的持久目录，不存在就建出来。
func attachmentsDirectory() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    let dir = base.appending(path: "Attachments", directoryHint: .isDirectory)
    guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
        return nil
    }
    return dir
}

/// 把一个本地文件拷进本次发送的文件夹，返回新地址；拷不动返回 nil。
/// 来源可能还在安全域里，能读就拷；`startAccessing` 返回 false
/// 不代表读不了，先试着拷，拷失败才认输。
func persistFileURL(_ url: URL, sendID: UUID) -> URL? {
    guard url.isFileURL else { return nil }
    guard let dir = attachmentsDirectory() else { return nil }
    let sendDir = dir.appending(path: sendID.uuidString, directoryHint: .isDirectory)
    do {
        try FileManager.default.createDirectory(at: sendDir, withIntermediateDirectories: true)
        var dest = sendDir.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            dest = sendDir.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    } catch {
        return nil
    }
}

// MARK: - 发送前持久化

/// 发送前把 media 里的本地文件拷到持久目录，返回新 media 和拷失败的
/// 名字。图片/视频/文件都拷；拷不动的那一项原样保留在返回值里，
/// 名字记进 failedNames，调用方拿它给用户一句明确提示。
func persistSentMedia(_ media: [MediaAttachment]) -> (media: [MediaAttachment], failedNames: [String]) {
    guard !media.isEmpty else { return (media, []) }
    let sendID = UUID()
    var failed: [String] = []
    let persisted = media.map { item -> MediaAttachment in
        switch item {
        case .image(let url, let width, let height):
            guard let dest = persistFileURL(url, sendID: sendID) else {
                failed.append(url.lastPathComponent)
                return item
            }
            return .image(url: dest, width: width, height: height)
        case .video(let url, let thumbURL, let duration):
            guard let dest = persistFileURL(url, sendID: sendID) else {
                failed.append(url.lastPathComponent)
                return item
            }
            var newThumb = thumbURL
            if let thumbURL, let destThumb = persistFileURL(thumbURL, sendID: sendID) {
                newThumb = destThumb
            }
            return .video(url: dest, thumbnailURL: newThumb, duration: duration)
        case .file(let url, let name, let size):
            guard let dest = persistFileURL(url, sendID: sendID) else {
                failed.append(name)
                return item
            }
            let newSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? size
            return .file(url: dest, name: name, size: newSize)
        }
    }
    return (persisted, failed)
}
