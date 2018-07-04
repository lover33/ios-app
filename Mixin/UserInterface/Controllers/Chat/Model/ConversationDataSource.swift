import UIKit
import AVKit
import Photos

extension Notification.Name {
    
    public enum ConversationDataSource {
        static let DidAddedMessagesOutsideVisibleBounds = Notification.Name("one.mixin.ios.conversation.datasource.add.message.outside.visible.bounds")
    }
    
}

class ConversationDataSource {
    
    private static let videoRequestOptions: PHVideoRequestOptions = {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.version = .current
        options.deliveryMode = .fastFormat
        return options
    }()
    
    let queue = DispatchQueue(label: "one.mixin.ios.message.processing")
    
    var ownerUser: UserItem?
    var firstUnreadMessageId: String?
    weak var tableView: ConversationTableView?
    
    private let messagesCountPerPage = 100
    private let layoutWidth = AppDelegate.current.window!.bounds.width
    private let me = AccountAPI.shared.account!
    private let semaphore = DispatchSemaphore(value: 1)

    private(set) var conversation: ConversationItem {
        didSet {
            category = conversation.category == ConversationCategory.CONTACT.rawValue ? .contact : .group
        }
    }
    private(set) var dates = [String]()
    private(set) var loadedMessageIds = Set<String>()
    private(set) var didLoadLatestMessage = false
    private(set) var category: Category
    
    private var highlight: Highlight?
    private var viewModels = [String: [MessageViewModel]]()
    private var didLoadEarliestMessage = false
    private var isLoadingAbove = false
    private var isLoadingBelow = false
    private var canInsertUnreadHint = true
    private var messageProcessingIsCancelled = false
    private var didInitializedData = false
    private var pendingChanges = [ConversationChange]()
    
    var conversationId: String {
        return conversation.conversationId
    }
    
    var lastIndexPath: IndexPath? {
        let section = dates.count - 1
        guard section >= 0, let rowCount = viewModels(for: section)?.count else {
            return nil
        }
        return IndexPath(row: rowCount - 1, section: section)
    }
    
    // MARK: - Interface
    init(conversation: ConversationItem, highlight: Highlight? = nil, ownerUser: UserItem? = nil) {
        self.conversation = conversation
        self.highlight = highlight
        self.ownerUser = ownerUser
        self.category = conversation.category == ConversationCategory.CONTACT.rawValue ? .contact : .group
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func initData() {
        NotificationCenter.default.addObserver(self, selector: #selector(conversationDidChange(_:)), name: .ConversationDidChange, object: nil)
        queue.async {
            guard !self.messageProcessingIsCancelled else {
                return
            }
            self.reload()
        }
    }
    
    func cancelMessageProcessing() {
        messageProcessingIsCancelled = true
        semaphore.signal()
        semaphore.signal()
    }
    
    func scrollToFirstUnreadMessageOrBottom() {
        guard let tableView = tableView else {
            return
        }
        if didLoadLatestMessage {
            if let firstUnreadMessageId = firstUnreadMessageId, let indexPath = indexPath(where: { $0.messageId == firstUnreadMessageId }) {
                tableView.scrollToRow(at: indexPath, at: .top, animated: true)
                self.firstUnreadMessageId = nil
            } else {
                tableView.scrollToBottom(animated: true)
            }
        } else {
            scrollToBottomAndReload(initialMessageId: firstUnreadMessageId)
        }
    }
    
    func loadMoreAboveIfNeeded() {
        guard !isLoadingAbove, !didLoadEarliestMessage else {
            return
        }
        isLoadingAbove = true
        let messagesCountPerPage = self.messagesCountPerPage
        let conversationId = self.conversationId
        let layoutWidth = self.layoutWidth
        queue.async {
            guard !self.messageProcessingIsCancelled, let firstDate = self.dates.first, let location = self.viewModels[firstDate]?.first?.message else {
                return
            }
            self.semaphore.wait()
            var messages = MessageDAO.shared.getMessages(conversationId: conversationId, aboveMessage: location, count: messagesCountPerPage)
            let didLoadEarliestMessage = messages.count < messagesCountPerPage
            self.didLoadEarliestMessage = didLoadEarliestMessage
            let shouldInsertEncryptionHint = self.canInsertEncryptionHint && didLoadEarliestMessage
            messages = messages.filter{ !self.loadedMessageIds.contains($0.messageId) }
            self.loadedMessageIds.formUnion(messages.map({ $0.messageId }))
            var (dates, viewModels) = self.viewModels(with: messages, fits: layoutWidth)
            if shouldInsertEncryptionHint, let firstDate = dates.first {
                let hint = MessageItem.encryptionHintMessage(conversationId: conversationId)
                let encryptionHintViewModel = self.viewModel(withMessage: hint, style: .bottomSeparator, fits: layoutWidth)
                viewModels[firstDate]?.insert(encryptionHintViewModel, at: 0)
            }
            if let lastDate = dates.last, let viewModelsBeforeInsertion = self.viewModels[lastDate] {
                let messagesBeforeInsertion = Array(viewModelsBeforeInsertion.prefix(2)).map({ $0.message })
                let messagesForTheDate = Array(messages.suffix(2)) + messagesBeforeInsertion
                let styles = Array(0..<messagesForTheDate.count).map{ self.style(forIndex: $0, messages: messagesForTheDate)}
                viewModels[lastDate]?.last?.style = styles[styles.count - messagesBeforeInsertion.count - 1]
                DispatchQueue.main.async {
                    guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                        return
                    }
                    if let viewModel = self.viewModels[lastDate]?.first {
                        viewModel.style = styles[styles.count - messagesBeforeInsertion.count]
                        if let indexPath = self.indexPath(where: { $0.messageId == viewModel.message.messageId }), let cell = tableView.cellForRow(at: indexPath) as? MessageCell {
                            cell.render(viewModel: viewModel)
                            tableView.beginUpdates()
                            tableView.endUpdates()
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                    return
                }
                for date in dates.reversed() {
                    let newViewModels = viewModels[date]!
                    if self.viewModels[date] == nil {
                        self.dates.insert(date, at: 0)
                        self.viewModels[date] = newViewModels
                    } else {
                        self.viewModels[date]!.insert(contentsOf: newViewModels, at: 0)
                    }
                }
                let bottomDistance = tableView.contentSize.height - tableView.contentOffset.y
                tableView.reloadData()
                tableView.contentOffset = CGPoint(x: tableView.contentOffset.x,
                                                  y: tableView.contentSize.height - bottomDistance)
                self.isLoadingAbove = false
                self.semaphore.signal()
            }
        }
    }
    
    func loadMoreBelowIfNeeded() {
        guard !isLoadingBelow, !didLoadLatestMessage else {
            return
        }
        isLoadingBelow = true
        highlight = nil
        let conversationId = self.conversationId
        let messagesCountPerPage = self.messagesCountPerPage
        let layoutWidth = self.layoutWidth
        queue.async {
            guard !self.messageProcessingIsCancelled, let lastDate = self.dates.last, let location = self.viewModels[lastDate]?.last?.message else {
                return
            }
            self.semaphore.wait()
            var messages = MessageDAO.shared.getMessages(conversationId: conversationId, belowMessage: location, count: messagesCountPerPage)
            self.didLoadLatestMessage = messages.count < messagesCountPerPage
            messages = messages.filter{ !self.loadedMessageIds.contains($0.messageId) }
            self.loadedMessageIds.formUnion(messages.map({ $0.messageId }))
            if self.canInsertUnreadHint, let firstUnreadMessageId = self.firstUnreadMessageId, let index = messages.index(where: { $0.messageId == firstUnreadMessageId }) {
                let firstUnreadMessage = messages[index]
                let hint = MessageItem.createMessage(category: MessageCategory.EXT_UNREAD.rawValue, conversationId: conversationId, createdAt: firstUnreadMessage.createdAt)
                messages.insert(hint, at: index)
                self.firstUnreadMessageId = nil
                self.canInsertUnreadHint = false
            }
            let (dates, viewModels) = self.viewModels(with: messages, fits: layoutWidth)
            if let firstDate = dates.first, let messagesBeforeAppend = self.viewModels[firstDate]?.suffix(2).map({ $0.message }) {
                let messagesForTheDate = messagesBeforeAppend + messages.prefix(2)
                let styles = Array(0..<messagesForTheDate.count).map{ self.style(forIndex: $0, messages: messagesForTheDate)}
                viewModels[firstDate]?.first?.style = styles[messagesBeforeAppend.count]
                DispatchQueue.main.async {
                    guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                        return
                    }
                    if let viewModel = self.viewModels[firstDate]?.last {
                        viewModel.style = styles[messagesBeforeAppend.count - 1]
                        if let indexPath = self.indexPath(where: { $0.messageId == viewModel.message.messageId }), let cell = tableView.cellForRow(at: indexPath) as? MessageCell {
                            cell.render(viewModel: viewModel)
                            tableView.beginUpdates()
                            tableView.endUpdates()
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                    return
                }
                if messages.count != 0 {
                    self.viewModels.values.flatMap({ $0 }).forEach {
                        ($0 as? TextMessageViewModel)?.removeHighlights()
                    }
                }
                for date in dates {
                    let newViewModels = viewModels[date]!
                    if self.viewModels[date] == nil {
                        self.dates.append(date)
                        self.viewModels[date] = newViewModels
                    } else {
                        self.viewModels[date]!.append(contentsOf: newViewModels)
                    }
                }
                tableView.reloadData()
                self.isLoadingBelow = false
                self.semaphore.signal()
            }
        }
    }
    
    func removeViewModel(at indexPath: IndexPath) -> (didRemoveRow: Bool, didRemoveSection: Bool) {
        var didRemoveRow = false
        var didRemoveSection = false
        let date = dates[indexPath.section]
        if let viewModel = viewModels[date]?.remove(at: indexPath.row) {
            didRemoveRow = true
            loadedMessageIds.remove(viewModel.message.messageId)
        }
        if let viewModels = viewModels[date], viewModels.isEmpty {
            if let index = dates.index(of: date) {
                didRemoveSection = true
                dates.remove(at: index)
            }
            self.viewModels[date] = nil
        }
        return (didRemoveRow, didRemoveSection)
    }
    
    func viewModels(for section: Int) -> [MessageViewModel]? {
        guard section < dates.count else {
            return nil
        }
        let date = dates[section]
        return viewModels[date]
    }
    
    func viewModel(for indexPath: IndexPath) -> MessageViewModel? {
        guard let viewModels = viewModels(for: indexPath.section), indexPath.row < viewModels.count else {
            return nil
        }
        return viewModels[indexPath.row]
    }
    
    func indexPath(where predicate: (MessageItem) -> Bool) -> IndexPath? {
        return indexPath(ofDates: dates, viewModels: viewModels, where: predicate)
    }
    
}

// MARK: - Callback
extension ConversationDataSource {
    
    @objc func conversationDidChange(_ sender: Notification) {
        guard let change = sender.object as? ConversationChange, change.conversationId == conversationId else {
            return
        }
        if didInitializedData {
            perform(change: change)
        } else {
            pendingChanges.append(change)
        }
    }
    
    private func perform(change: ConversationChange) {
        switch change.action {
        case .reload:
            highlight = nil
            ConversationViewController.positions[conversationId] = nil
            reload()
        case .update(let conversation):
            self.conversation = conversation
        case .addMessage(let message):
            addMessage(message)
        case .updateGroupIcon(let iconUrl):
            conversation.iconUrl = iconUrl
        case .updateMessage(let messageId):
            updateMessage(messageId: messageId)
        case .updateMessageStatus(let messageId, let newStatus):
            updateMessageStatus(messageId: messageId, status: newStatus)
        case .updateMediaStatus(let messageId, let mediaStatus):
            updateMessageMediaStatus(messageId: messageId, mediaStatus: mediaStatus)
        case .updateUploadProgress(let messageId, let progress):
            updateMediaProgress(messageId: messageId, progress: progress)
        case .updateDownloadProgress(let messageId, let progress):
            updateMediaProgress(messageId: messageId, progress: progress)
        default:
            break
        }
    }
    
    private func addMessage(_ message: MessageItem) {
        guard !loadedMessageIds.contains(message.messageId) else {
            return
        }
        let messageIsSentByMe = message.userId == me.user_id
        if !messageIsSentByMe, message.status == MessageStatus.DELIVERED.rawValue {
            SendMessageService.shared.sendReadMessage(messageId: message.messageId)
        }
        if !didLoadLatestMessage {
            if messageIsSentByMe {
                queue.async {
                    guard !self.messageProcessingIsCancelled else {
                        return
                    }
                    DispatchQueue.main.async {
                        self.scrollToBottomAndReload()
                    }
                }
            } else {
                NotificationCenter.default.postOnMain(name: Notification.Name.ConversationDataSource.DidAddedMessagesOutsideVisibleBounds, object: 1)
            }
        } else {
            queue.async {
                guard !self.messageProcessingIsCancelled else {
                    return
                }
                self.addMessageAndDisplay(message: message)
            }
        }
    }
    
    private func updateMessageStatus(messageId: String, status: MessageStatus) {
        guard let indexPath = indexPath(where: { $0.messageId == messageId }), let viewModel = viewModel(for: indexPath) as? DetailInfoMessageViewModel else {
            return
        }
        viewModel.status = status.rawValue
        if let cell = tableView?.cellForRow(at: indexPath) as? DetailInfoMessageCell {
            cell.render(viewModel: viewModel)
        }
    }
    
    private func updateMessageMediaStatus(messageId: String, mediaStatus: MediaStatus) {
        guard let indexPath = indexPath(where: { $0.messageId == messageId }) else {
            return
        }
        if let viewModel = viewModel(for: indexPath) as? MessageViewModel & AttachmentLoadingViewModel {
            viewModel.mediaStatus = mediaStatus.rawValue
            if let cell = tableView?.cellForRow(at: indexPath) as? MessageCell {
                cell.render(viewModel: viewModel)
            }
        }
    }
    
    private func updateMediaProgress(messageId: String, progress: Double) {
        guard let indexPath = indexPath(where: { $0.messageId == messageId }), let viewModel = viewModel(for: indexPath) as? MessageViewModel & AttachmentLoadingViewModel else {
            return
        }
        viewModel.progress = progress
        if let cell = tableView?.cellForRow(at: indexPath) as? AttachmentLoadingMessageCell {
            cell.updateProgress(viewModel: viewModel)
        }
    }
    
    private func updateMessage(messageId: String) {
        queue.async {
            guard !self.messageProcessingIsCancelled else {
                return
            }
            guard let indexPath = self.indexPath(where: { $0.messageId == messageId }) else {
                return
            }
            guard let message = MessageDAO.shared.getFullMessage(messageId: messageId) else {
                return
            }
            
            if message.status == MessageStatus.DELIVERED.rawValue && message.userId != AccountAPI.shared.accountUserId {
                SendMessageService.shared.sendReadMessage(messageId: message.messageId)
            }
            
            self.semaphore.wait()
            DispatchQueue.main.async {
                guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                    return
                }
                let date = DateFormatter.yyyymmdd.string(from: message.createdAt.toUTCDate())
                if let style = self.viewModels[date]?[indexPath.row].style {
                    let viewModel = self.viewModel(withMessage: message, style: style, fits: self.layoutWidth)
                    self.viewModels[date]?[indexPath.row] = viewModel
                    tableView.reloadRows(at: [indexPath], with: .automatic)
                }
                self.semaphore.signal()
            }
        }
    }
    
}

// MARK: - Send Message
extension ConversationDataSource {
    
    func sendMessage(type: MessageCategory, quoteMessageId: String? = nil , value: Any) {
        let isGroupMessage = category == .group
        let ownerUser = self.ownerUser
        var message = Message.createMessage(category: type.rawValue, conversationId: conversationId, userId: me.user_id)
        message.quoteMessageId = quoteMessageId
        if type == .SIGNAL_TEXT, let text = value as? String {
            message.content = text
            queue.async {
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            }
        } else if type == .SIGNAL_DATA, let url = value as? URL {
            queue.async {
                guard FileManager.default.fileSize(url.path) > 0 else {
                    NotificationCenter.default.postOnMain(name: .ErrorMessageDidAppear, object: Localized.CHAT_SEND_FILE_FAILED)
                    return
                }
                var filename = url.lastPathComponent.substring(endChar: ".").lowercased().md5()
                var targetUrl = MixinFile.url(ofChatDirectory: .files, filename: "\(filename).\(url.pathExtension)")
                do {
                    if FileManager.default.fileExists(atPath: targetUrl.path) {
                        if !FileManager.default.compare(path1: url.path, path2: targetUrl.path) {
                            filename = UUID().uuidString.lowercased()
                            targetUrl = MixinFile.url(ofChatDirectory: .videos, filename: "\(filename).\(url.pathExtension)")
                            try FileManager.default.moveItem(at: url, to: targetUrl)
                        }
                    } else {
                        try FileManager.default.moveItem(at: url, to: targetUrl)
                    }
                } catch {
                    NotificationCenter.default.postOnMain(name: .ErrorMessageDidAppear, object: Localized.CHAT_SEND_FILE_FAILED)
                    return
                }
                message.name = url.lastPathComponent
                message.mediaSize = FileManager.default.fileSize(targetUrl.path)
                message.mediaMimeType = FileManager.default.mimeType(ext: targetUrl.pathExtension)
                message.mediaUrl = "\(filename).\(targetUrl.pathExtension)"
                message.mediaStatus = MediaStatus.PENDING.rawValue
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            }
        } else if type == .SIGNAL_VIDEO, let value = value as? (URL, AVAsset) {
            queue.async {
                let url = value.0
                let asset = value.1
                guard asset.duration.isValid, let videoTrack = asset.tracks(withMediaType: .video).first else {
                    NotificationCenter.default.postOnMain(name: .ErrorMessageDidAppear, object: Localized.CHAT_SEND_VIDEO_FAILED)
                    return
                }
                let filename = url.lastPathComponent.substring(endChar: ".")
                let thumbnailFilename = filename + ExtensionName.jpeg.withDot
                if let thumbnail = UIImage(withFirstFrameOfVideoAtURL: url) {
                    let thumbnailURL = MixinFile.url(ofChatDirectory: .videos, filename: thumbnailFilename)
                    thumbnail.saveToFile(path: thumbnailURL)
                    message.thumbImage = thumbnail.getBlurThumbnail().toBase64()
                } else {
                    NotificationCenter.default.postOnMain(name: .ErrorMessageDidAppear, object: Localized.CHAT_SEND_VIDEO_FAILED)
                    return
                }
                message.mediaDuration = Int64(asset.duration.seconds * millisecondsPerSecond)
                let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
                message.mediaWidth = Int(abs(size.width))
                message.mediaHeight = Int(abs(size.height))
                message.mediaSize = FileManager.default.fileSize(url.path)
                message.mediaMimeType = FileManager.default.mimeType(ext: url.pathExtension)
                message.mediaUrl = url.lastPathComponent
                message.mediaStatus = MediaStatus.PENDING.rawValue
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            }
        } else if type == .SIGNAL_AUDIO, let value = value as? (tempUrl: URL, metadata: MXNAudioMetadata) {
            queue.async {
                guard FileManager.default.fileSize(value.tempUrl.path) > 0 else {
                    NotificationCenter.default.postOnMain(name: .ErrorMessageDidAppear, object: Localized.CHAT_SEND_AUDIO_FAILED)
                    return
                }
                let url = MixinFile.url(ofChatDirectory: .audios, filename: UUID().uuidString.lowercased() + ExtensionName.ogg.withDot)
                do {
                    try FileManager.default.moveItem(at: value.tempUrl, to: url)
                    message.mediaSize = FileManager.default.fileSize(url.path)
                    message.mediaMimeType = FileManager.default.mimeType(ext: url.pathExtension)
                    message.mediaUrl = url.lastPathComponent
                    message.mediaStatus = MediaStatus.PENDING.rawValue
                    message.mediaWaveform = value.metadata.waveform
                    message.mediaDuration = Int64(value.metadata.duration)
                    SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
                } catch {
                    NotificationCenter.default.postOnMain(name: .ErrorMessageDidAppear, object: Localized.CHAT_SEND_AUDIO_FAILED)
                }
            }
        } else if type == .SIGNAL_STICKER, let sticker = value as? Sticker {
            message.mediaStatus = MediaStatus.PENDING.rawValue
            message.mediaUrl = sticker.assetUrl
            message.stickerId = sticker.stickerId
            queue.async {
                let albumId = AlbumDAO.shared.getAlbum(stickerId: sticker.stickerId)?.albumId
                let transferData = TransferStickerData(stickerId: sticker.stickerId, name: sticker.name, albumId: albumId)
                message.content = try! JSONEncoder().encode(transferData).base64EncodedString()
                SendMessageService.shared.sendMessage(message: message, ownerUser: ownerUser, isGroupMessage: isGroupMessage)
            }
        }
    }
    
}

// MARK: - Private works
extension ConversationDataSource {
    
    private var canInsertEncryptionHint: Bool {
        if let ownerUser = ownerUser, ownerUser.isBot {
            return false
        } else {
            return true
        }
    }
    
    private func reload(initialMessageId: String? = nil) {
        semaphore.wait()
        canInsertUnreadHint = true
        var didLoadEarliestMessage = false
        var didLoadLatestMessage = false
        var messages: [MessageItem]
        let initialMessageId = initialMessageId
            ?? highlight?.messageId
            ?? ConversationViewController.positions[conversationId]?.messageId
        if let initialMessageId = initialMessageId {
            messages = MessageDAO.shared.getMessages(conversationId: conversationId, aroundMessageId: initialMessageId, count: messagesCountPerPage)
            if highlight == nil, initialMessageId != firstUnreadMessageId {
                firstUnreadMessageId = MessageDAO.shared.firstUnreadMessage(conversationId: conversationId)?.messageId
            }
        } else if let firstUnreadMessageId = MessageDAO.shared.firstUnreadMessage(conversationId: conversationId)?.messageId {
            messages = MessageDAO.shared.getMessages(conversationId: conversationId, aroundMessageId: firstUnreadMessageId, count: messagesCountPerPage)
            self.firstUnreadMessageId = firstUnreadMessageId
        } else {
            messages = MessageDAO.shared.getLastNMessages(conversationId: conversationId, count: messagesCountPerPage)
            didLoadLatestMessage = true
            firstUnreadMessageId = nil
        }
        loadedMessageIds = Set(messages.map({ $0.messageId }))
        var shouldInsertEncryptionHint = false
        if messages.count > 0, highlight == nil, let firstUnreadMessageId = self.firstUnreadMessageId, let firstUnreadIndex = messages.index(where: { $0.messageId == firstUnreadMessageId }) {
            let firstUnreadMessge = messages[firstUnreadIndex]
            let hint = MessageItem.createMessage(category: MessageCategory.EXT_UNREAD.rawValue, conversationId: conversationId, createdAt: firstUnreadMessge.createdAt)
            messages.insert(hint, at: firstUnreadIndex)
            self.firstUnreadMessageId = nil
            canInsertUnreadHint = false
        }
        if messages.count < messagesCountPerPage {
            didLoadEarliestMessage = true
            didLoadLatestMessage = true
            shouldInsertEncryptionHint = true
        }
        var (dates, viewModels) = self.viewModels(with: messages, fits: layoutWidth)
        if canInsertEncryptionHint && shouldInsertEncryptionHint {
            let date: String
            if let firstDate = dates.first {
                date = firstDate
            } else {
                date = DateFormatter.yyyymmdd.string(from: Date())
                dates.append(date)
            }
            let hint = MessageItem.encryptionHintMessage(conversationId: self.conversationId)
            let viewModel = self.viewModel(withMessage: hint, style: .bottomSeparator, fits: layoutWidth)
            if viewModels[date] != nil {
                viewModels[date]?.insert(viewModel, at: 0)
            } else {
                viewModels[date] = [viewModel]
            }
        }
        var initialIndexPath: IndexPath?
        var offset: CGFloat = 0
        let unreadMessagesCount = MessageDAO.shared.getUnreadMessagesCount(conversationId: conversationId)
        
        if let initialMessageId = highlight?.messageId {
            initialIndexPath = indexPath(ofDates: dates, viewModels: viewModels, where: { $0.messageId == initialMessageId })
            offset -= ConversationDateHeaderView.height
        } else if let position = ConversationViewController.positions[conversationId] {
            initialIndexPath = indexPath(ofDates: dates, viewModels: viewModels, where: { $0.messageId == position.messageId })
            offset = position.offset
        } else if let unreadHintIndexPath = indexPath(ofDates: dates, viewModels: viewModels, where: { $0.category == MessageCategory.EXT_UNREAD.rawValue }) {
            if unreadHintIndexPath == IndexPath(row: 1, section: 0), viewModels[dates[0]]?.first?.message.category == MessageCategory.EXT_ENCRYPTION.rawValue {
                initialIndexPath = IndexPath(row: 0, section: 0)
            } else {
                initialIndexPath = unreadHintIndexPath
            }
            offset -= ConversationDateHeaderView.height
        }
        DispatchQueue.main.async {
            guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                return
            }
            self.dates = dates
            self.viewModels = viewModels
            tableView.reloadData()
            self.didLoadEarliestMessage = didLoadEarliestMessage
            self.didLoadLatestMessage = didLoadLatestMessage
            if let initialIndexPath = initialIndexPath {
                if tableView.contentSize.height - tableView.bounds.height > 0 {
                    let rect = tableView.rectForRow(at: initialIndexPath)
                    let maxY = tableView.contentSize.height - tableView.bounds.height + tableView.contentInset.bottom
                    let y = ceil(min(maxY, max(0, rect.origin.y + offset)))
                    tableView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                }
            } else {
                tableView.scrollToBottom(animated: false)
            }
            if ConversationViewController.positions[self.conversationId] != nil && !tableView.visibleCells.contains(where: { $0 is UnreadHintMessageCell }) {
                NotificationCenter.default.post(name: Notification.Name.ConversationDataSource.DidAddedMessagesOutsideVisibleBounds, object: unreadMessagesCount)
            }
            SendMessageService.shared.sendReadMessages(conversationId: self.conversationId)
            self.didInitializedData = true
            for change in self.pendingChanges {
                self.perform(change: change)
            }
            self.pendingChanges = []
            self.semaphore.signal()
        }
    }
    
    private func indexPath(ofDates dates: [String], viewModels: [String: [MessageViewModel]], where predicate: (MessageItem) -> Bool) -> IndexPath? {
        for (section, date) in dates.enumerated() {
            let viewModels = viewModels[date]!
            for (row, viewModel) in viewModels.enumerated() {
                if predicate(viewModel.message) {
                    return IndexPath(row: row, section: section)
                }
            }
        }
        return nil
    }
    
    typealias CategorizedViewModels = (dates: [String], viewModels: [String: [MessageViewModel]])
    private func viewModels(with messages: [MessageItem], fits layoutWidth: CGFloat) -> CategorizedViewModels {
        var dates = [String]()
        var cataloguedMessages = [String: [MessageItem]]()
        for i in 0..<messages.count {
            let message = messages[i]
            let date = DateFormatter.yyyymmdd.string(from: message.createdAt.toUTCDate())
            if cataloguedMessages[date] != nil {
                cataloguedMessages[date]!.append(message)
            } else {
                cataloguedMessages[date] = [message]
            }
        }
        dates = cataloguedMessages.keys.sorted(by: <)
        
        var viewModels = [String: [MessageViewModel]]()
        for date in dates {
            let messages = cataloguedMessages[date] ?? []
            for (row, message) in messages.enumerated() {
                let style = self.style(forIndex: row, messages: messages)
                let viewModel = self.viewModel(withMessage: message, style: style, fits: layoutWidth)
                if viewModels[date] != nil {
                    viewModels[date]!.append(viewModel)
                } else {
                    viewModels[date] = [viewModel]
                }
            }
        }
        return (dates: dates, viewModels: viewModels)
    }
    
    private func viewModel(withMessage message: MessageItem, style: MessageViewModel.Style, fits layoutWidth: CGFloat) -> MessageViewModel {
        let viewModel: MessageViewModel
        if message.status == MessageStatus.FAILED.rawValue {
            viewModel = DecryptionFailedMessageViewModel(message: message, style: style, fits: layoutWidth)
        } else {
            if message.quoteMessageId != nil && message.quoteContent != nil {
                viewModel = QuoteTextMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category.hasSuffix("_TEXT") {
                let textViewModel = TextMessageViewModel(message: message, style: style, fits: layoutWidth)
                if let keyword = highlight?.keyword {
                    textViewModel.highlight(keyword: keyword)
                }
                viewModel = textViewModel
            } else if message.category.hasSuffix("_IMAGE") {
                viewModel = PhotoMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category.hasSuffix("_STICKER") {
                viewModel = StickerMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category.hasSuffix("_DATA") {
                viewModel = DataMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category.hasSuffix("_VIDEO") {
                viewModel = VideoMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category.hasSuffix("_AUDIO") {
                viewModel = AudioMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category.hasSuffix("_CONTACT") {
                viewModel = ContactMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category == MessageCategory.SYSTEM_ACCOUNT_SNAPSHOT.rawValue {
                viewModel = TransferMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category == MessageCategory.SYSTEM_CONVERSATION.rawValue {
                viewModel = SystemMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category == MessageCategory.APP_BUTTON_GROUP.rawValue {
                viewModel = AppButtonGroupViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category == MessageCategory.APP_CARD.rawValue {
                viewModel = AppCardMessageViewModel(message: message, style: style, fits: layoutWidth)
            } else if message.category == MessageCategory.EXT_UNREAD.rawValue {
                viewModel = MessageViewModel(message: message, style: style, fits: layoutWidth)
                viewModel.cellHeight = 38
            } else if message.category == MessageCategory.EXT_ENCRYPTION.rawValue {
                viewModel = EncryptionHintViewModel(message: message, style: style, fits: layoutWidth)
            } else {
                viewModel = UnknownMessageViewModel(message: message, style: style, fits: layoutWidth)
            }
        }
        return viewModel
    }
    
    private func style(forIndex index: Int, messages: [MessageItem]) -> MessageViewModel.Style {
        let message = messages[index]
        let isFirstMessage = (index == 0)
        let isLastMessage = (index == messages.count - 1)
        var style: MessageViewModel.Style = []
        if message.userId != me.user_id {
            style = .received
        }
        if isLastMessage
            || messages[index + 1].userId != message.userId
            || messages[index + 1].isExtensionMessage
            || messages[index + 1].isSystemMessage {
            style.insert(.tail)
        }
        if message.category == MessageCategory.EXT_ENCRYPTION.rawValue {
            style.insert(.bottomSeparator)
        } else if !isLastMessage && (message.isSystemMessage
            || messages[index + 1].userId != message.userId
            || messages[index + 1].isSystemMessage
            || messages[index + 1].isExtensionMessage) {
            style.insert(.bottomSeparator)
        }
        if message.isRepresentativeMessage(conversation: conversation) {
            if (isFirstMessage && !message.isExtensionMessage && !message.isSystemMessage)
                || (!isFirstMessage && (messages[index - 1].userId != message.userId || messages[index - 1].isExtensionMessage || messages[index - 1].isSystemMessage)) {
                style.insert(.fullname)
            }
        }
        return style
    }
    
    private func addMessageAndDisplay(message: MessageItem) {
        loadedMessageIds.insert(message.messageId)
        semaphore.wait()
        let messageIsSentByMe = message.userId == me.user_id
        let date = DateFormatter.yyyymmdd.string(from: message.createdAt.toUTCDate())
        let lastIndexPathBeforeInsertion = lastIndexPath
        var style: MessageViewModel.Style = []
        if !messageIsSentByMe {
            style.insert(.received)
        }
        let needsInsertNewSection: Bool
        let section: Int
        let row: Int
        let isLastCell: Bool
        let viewModel: MessageViewModel
        if let viewModels = viewModels[date] {
            needsInsertNewSection = false
            section = dates.index(of: date)!
            if let index = viewModels.index(where: { $0.message.createdAt > message.createdAt }) {
                isLastCell = false
                row = index
            } else {
                isLastCell = true
                row = viewModels.count
                style.insert(.tail)
            }
            if row - 1 >= 0 {
                let previousViewModel = viewModels[row - 1]
                let previousViewModelIsFromDifferentUser = previousViewModel.message.userId != message.userId
                if previousViewModel.message.isSystemMessage || message.isSystemMessage || message.isExtensionMessage {
                    if !messageIsSentByMe {
                        style.insert(.fullname)
                    }
                    previousViewModel.style.insert(.bottomSeparator)
                } else if previousViewModelIsFromDifferentUser {
                    previousViewModel.style.insert(.bottomSeparator)
                    previousViewModel.style.insert(.tail)
                } else {
                    previousViewModel.style.remove(.bottomSeparator)
                    previousViewModel.style.remove(.tail)
                }
                if message.isRepresentativeMessage(conversation: conversation) && style.contains(.received) && previousViewModelIsFromDifferentUser {
                    style.insert(.fullname)
                }
                DispatchQueue.main.async {
                    guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                        return
                    }
                    if let previousIndexPath = self.lastIndexPath, let previousCell = tableView.cellForRow(at: previousIndexPath) as? MessageCell {
                        previousCell.render(viewModel: previousViewModel)
                    }
                }
            }
            viewModel = self.viewModel(withMessage: message, style: style, fits: layoutWidth)
            if !isLastCell {
                let nextViewModel = viewModels[row]
                if viewModel.message.userId != nextViewModel.message.userId {
                    viewModel.style.insert(.tail)
                    viewModel.style.insert(.bottomSeparator)
                    if nextViewModel.message.isRepresentativeMessage(conversation: conversation) && nextViewModel.style.contains(.received) {
                        nextViewModel.style.insert(.fullname)
                    }
                } else {
                    viewModel.style.remove(.tail)
                    viewModel.style.remove(.bottomSeparator)
                    nextViewModel.style.remove(.fullname)
                }
                DispatchQueue.main.async {
                    guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                        return
                    }
                    let nextIndexPath = IndexPath(row: row, section: self.dates.index(of: date)!)
                    if let nextCell = tableView.cellForRow(at: nextIndexPath) as? MessageCell {
                        nextCell.render(viewModel: nextViewModel)
                    }
                }
            }
        } else {
            needsInsertNewSection = true
            section = dates.index(where: { $0 > date }) ?? dates.count
            row = 0
            isLastCell = section == dates.count
            if style.contains(.received) && message.isRepresentativeMessage(conversation: conversation) {
                style.insert(.fullname)
            }
            viewModel = self.viewModel(withMessage: message, style: style, fits: layoutWidth)
        }
        DispatchQueue.main.async {
            guard let tableView = self.tableView, !self.messageProcessingIsCancelled else {
                return
            }
            let lastMessageIsVisibleBeforeInsertion: Bool
            if let lastIndexPathBeforeInsertion = lastIndexPathBeforeInsertion, let visibleIndexPaths = tableView.indexPathsForVisibleRows, visibleIndexPaths.contains(lastIndexPathBeforeInsertion) {
                lastMessageIsVisibleBeforeInsertion = true
            } else {
                lastMessageIsVisibleBeforeInsertion = false
            }
            UIView.setAnimationsEnabled(false)
            tableView.beginUpdates()
            let indexPath = IndexPath(row: row, section: section)
            if needsInsertNewSection {
                self.dates.insert(date, at: section)
                self.viewModels[date] = [viewModel]
                tableView.insertSections(IndexSet(integer: indexPath.section), with: .none)
            } else {
                self.viewModels[date]!.insert(viewModel, at: row)
                tableView.insertRows(at: [indexPath], with: .none)
            }
            if tableView.tableFooterView != nil && messageIsSentByMe {
                tableView.tableFooterView = nil
            }
            tableView.endUpdates()
            UIView.setAnimationsEnabled(true)
            let shouldScrollToNewMessage = !tableView.isTracking
                && !tableView.isDecelerating
                && isLastCell
                && (lastMessageIsVisibleBeforeInsertion || messageIsSentByMe)
            if shouldScrollToNewMessage {
                CATransaction.perform(blockWithTransaction: {
                    tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
                }, completion: {
                    self.semaphore.signal()
                })
            } else {
                NotificationCenter.default.postOnMain(name: Notification.Name.ConversationDataSource.DidAddedMessagesOutsideVisibleBounds, object: 1)
                self.semaphore.signal()
            }
        }
    }
    
    private func scrollToBottomAndReload(initialMessageId: String? = nil) {
        guard !self.messageProcessingIsCancelled else {
            return
        }
        didLoadEarliestMessage = true
        didLoadLatestMessage = true
        tableView?.scrollToBottom(animated: true)
        highlight = nil
        ConversationViewController.positions[conversationId] = nil
        queue.async {
            guard !self.messageProcessingIsCancelled else {
                return
            }
            self.reload(initialMessageId: initialMessageId)
        }
    }
    
}

// MARK: - Embedded class
extension ConversationDataSource {
    
    enum Category {
        case group
        case contact
    }
    
    struct Highlight {
        let keyword: String
        let messageId: String
    }
    
}

extension MessageItem {
    
    static func encryptionHintMessage(conversationId: String) -> MessageItem {
        let message = MessageItem.createMessage(category: MessageCategory.EXT_ENCRYPTION.rawValue, conversationId: conversationId, createdAt: "")
        message.content = Localized.CHAT_CELL_TITLE_ENCRYPTION
        message.status = MessageStatus.READ.rawValue
        return message
    }
    
}
