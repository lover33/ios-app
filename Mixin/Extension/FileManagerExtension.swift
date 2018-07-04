import Foundation
import Bugsnag
import Zip
import ImageIO

extension FileManager {

    func fileSize(_ path: String) -> Int64 {
        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: path)[FileAttributeKey.size] as? NSNumber else {
            return 0
        }
        return fileSize?.int64Value ?? 0
    }

    func fileName(_ path: String) -> String {
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func compare(path1: String, path2: String) -> Bool {
        return fileSize(path1) == fileSize(path2) && contentsEqual(atPath: path1, andPath: path2)
    }

    func isStillImage(_ path: String) -> Bool {
        guard let handler = FileHandle(forReadingAtPath: path) else {
            return false
        }
        defer {
            handler.closeFile()
        }
        guard let c = handler.readData(ofLength: 1).bytes.first else {
            return false
        }
        // 0xFF => image/jpeg
        // 0x89 => image/png
        return c == 0x89 || c == 0xFF
    }

    func imageSize(_ path: String) -> CGSize {
        let imageFileURL = URL(fileURLWithPath: path)
        guard let imageSource = CGImageSourceCreateWithURL(imageFileURL as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? NSNumber, let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return UIImage(contentsOfFile: path)?.size ?? CGSize.zero
        }
        return CGSize(width: width.intValue, height: height.intValue)
    }

    func createNobackupDirectory(_ directory: URL) -> Bool {
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            return true
        }
        do {
            var dir = directory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
            return true
        } catch let error {
            print("======FileManagerExtension...error:\(error)")
            return false
        }
    }

    func removeDirectoryChildFiles(_ directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files {
            try? FileManager.default.removeItem(atPath: directory.appendingPathComponent(file).path)
        }
    }

    func mimeType(ext: String) -> String {
        return FileManager.mimeTypes[ext.lowercased()] ?? FileManager.defaultMimeType
    }

    func pathExtension(mimeType: String) -> String {
        guard !mimeType.isEmpty else {
            return "FILE"
        }
        for (key, value) in FileManager.mimeTypes {
            guard value == mimeType else {
                continue
            }
            let result = key.uppercased()
            guard result.count <= 4 else {
                return String(result.prefix(4))
            }
            return result
        }
        return "FILE"
    }

    private static let defaultMimeType = "application/octet-stream"

    private static let mimeTypes = [
        "html": "text/html",
        "htm": "text/html",
        "shtml": "text/html",
        "css": "text/css",
        "xml": "text/xml",
        "gif": "image/gif",
        "jpeg": "image/jpeg",
        "jpg": "image/jpeg",
        "js": "application/javascript",
        "atom": "application/atom+xml",
        "rss": "application/rss+xml",
        "mml": "text/mathml",
        "txt": "text/plain",
        "jad": "text/vnd.sun.j2me.app-descriptor",
        "wml": "text/vnd.wap.wml",
        "htc": "text/x-component",
        "png": "image/png",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "wbmp": "image/vnd.wap.wbmp",
        "ico": "image/x-icon",
        "jng": "image/x-jng",
        "bmp": "image/x-ms-bmp",
        "svg": "image/svg+xml",
        "svgz": "image/svg+xml",
        "webp": "image/webp",
        "woff": "application/font-woff",
        "jar": "application/java-archive",
        "war": "application/java-archive",
        "ear": "application/java-archive",
        "json": "application/json",
        "hqx": "application/mac-binhex40",
        "doc": "application/msword",
        "pdf": "application/pdf",
        "ps": "application/postscript",
        "eps": "application/postscript",
        "ai": "application/postscript",
        "rtf": "application/rtf",
        "m3u8": "application/vnd.apple.mpegurl",
        "xls": "application/vnd.ms-excel",
        "eot": "application/vnd.ms-fontobject",
        "ppt": "application/vnd.ms-powerpoint",
        "wmlc": "application/vnd.wap.wmlc",
        "kml": "application/vnd.google-earth.kml+xml",
        "kmz": "application/vnd.google-earth.kmz",
        "7z": "application/x-7z-compressed",
        "cco": "application/x-cocoa",
        "jardiff": "application/x-java-archive-diff",
        "jnlp": "application/x-java-jnlp-file",
        "run": "application/x-makeself",
        "pl": "application/x-perl",
        "pm": "application/x-perl",
        "prc": "application/x-pilot",
        "pdb": "application/x-pilot",
        "rar": "application/x-rar-compressed",
        "rpm": "application/x-redhat-package-manager",
        "sea": "application/x-sea",
        "swf": "application/x-shockwave-flash",
        "sit": "application/x-stuffit",
        "tcl": "application/x-tcl",
        "tk": "application/x-tcl",
        "der": "application/x-x509-ca-cert",
        "pem": "application/x-x509-ca-cert",
        "crt": "application/x-x509-ca-cert",
        "xpi": "application/x-xpinstall",
        "xhtml": "application/xhtml+xml",
        "xspf": "application/xspf+xml",
        "zip": "application/zip",
        "bin": "application/octet-stream",
        "exe": "application/octet-stream",
        "dll": "application/octet-stream",
        "deb": "application/octet-stream",
        "dmg": "application/octet-stream",
        "iso": "application/octet-stream",
        "img": "application/octet-stream",
        "msi": "application/octet-stream",
        "msp": "application/octet-stream",
        "msm": "application/octet-stream",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "mid": "audio/midi",
        "midi": "audio/midi",
        "kar": "audio/midi",
        "mp3": "audio/mpeg",
        "ogg": "audio/ogg",
        "m4a": "audio/x-m4a",
        "ra": "audio/x-realaudio",
        "3gpp": "video/3gpp",
        "3gp": "video/3gpp",
        "ts": "video/mp2t",
        "mp4": "video/mp4",
        "mpeg": "video/mpeg",
        "mpg": "video/mpeg",
        "mov": "video/quicktime",
        "webm": "video/webm",
        "flv": "video/x-flv",
        "m4v": "video/x-m4v",
        "mng": "video/x-mng",
        "asx": "video/x-ms-asf",
        "asf": "video/x-ms-asf",
        "wmv": "video/x-ms-wmv",
        "avi": "video/x-msvideo"
    ]
}

extension FileManager {

    private static let dispatchQueue = DispatchQueue(label: "one.mixin.messenger.queue.log")
    private static var conversations = [String: Conversation]()

    func writeLog(log: String, newSection: Bool = false) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: MixinFile.logPath.path) else {
            return
        }
        for file in files {
            let filename = MixinFile.logPath.appendingPathComponent(file).lastPathComponent.substring(endChar: ".")
            if log.hasPrefix("No sender key for:") {
                if log.contains(filename) {
                    FileManager.default.writeLog(conversationId: filename, log: log, commomLog: false, newSection: newSection)
                }
            } else {
                FileManager.default.writeLog(conversationId: filename, log: log, commomLog: true, newSection: newSection)
            }
        }
    }

    func writeLog(conversationId: String, log: String, commomLog: Bool = false, newSection: Bool = false) {
        guard !conversationId.isEmpty else {
            return
        }
        FileManager.dispatchQueue.async {
            var log = log + "...\(DateFormatter.filename.string(from: Date()))\n"
            if newSection {
                log += "------------------------------\n"
            }
            let url = MixinFile.logPath.appendingPathComponent("\(conversationId).txt")
            let path = url.path
            do {
                if FileManager.default.fileExists(atPath: path) && FileManager.default.fileSize(path) > 1024 * 1024 * 2 {
                    guard let fileHandle = FileHandle(forUpdatingAtPath: path) else {
                        return
                    }
                    fileHandle.seek(toFileOffset: 1024 * 1024 * 1 + 1024 * 896)
                    let lastString = String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8)
                    fileHandle.closeFile()
                    try FileManager.default.removeItem(at: url)
                    try lastString?.write(toFile: path, atomically: true, encoding: .utf8)
                }

                if FileManager.default.fileExists(atPath: path) {
                    guard let data = log.data(using: .utf8) else {
                        return
                    }
                    guard let fileHandle = FileHandle(forUpdatingAtPath: path) else {
                        return
                    }
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    try log.write(toFile: path, atomically: true, encoding: .utf8)
                }
            } catch {
                #if DEBUG
                    print("======FileManagerExtension...writeLog...error:\(error)")
                #endif
                Bugsnag.notifyError(error)
            }
        }
    }

    func exportLog(conversationId: String) -> URL? {
        let conversationFile = MixinFile.logPath.appendingPathComponent("\(conversationId).txt")
        let filename = "\(AccountAPI.shared.accountIdentityNumber)_\(DateFormatter.filename.string(from: Date()))"
        do {
            return try Zip.quickZipFiles([conversationFile], fileName: filename)
        } catch {
            #if DEBUG
                print("======FileManagerExtension...exportLog...error:\(error)")
            #endif
        }
        return nil
    }
}
