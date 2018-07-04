import Foundation
import Bugsnag

class VideoDownloadJob: AttachmentDownloadJob {
    
    override lazy var fileName = "\(message.messageId).\(FileManager.default.pathExtension(mimeType: message.mediaMimeType ?? ""))"
    override lazy var fileUrl = MixinFile.url(ofChatDirectory: .videos, filename: fileName)
    
    private lazy var thumbnailUrl = MixinFile.url(ofChatDirectory: .videos, filename: messageId + ExtensionName.jpeg.withDot)

    override class func jobId(messageId: String) -> String {
        return "video-download-\(messageId)"
    }
    
    override func getJobId() -> String {
        return VideoDownloadJob.jobId(messageId: messageId)
    }
    
    override func taskFinished() {
        super.taskFinished()
        if stream?.streamError == nil {
            let thumbnail = UIImage(withFirstFrameOfVideoAtURL: fileUrl)
            thumbnail?.saveToFile(path: thumbnailUrl)
        }
    }
    
}
