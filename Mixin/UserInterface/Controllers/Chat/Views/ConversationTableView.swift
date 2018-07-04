import UIKit

fileprivate extension Selector {
    static let reply = #selector(ConversationTableView.replyAction(_:))
    static let delete = #selector(ConversationTableView.deleteAction(_:))
    static let forward = #selector(ConversationTableView.forwardAction(_:))
    static let copy = #selector(ConversationTableView.copyAction(_:))
    static let addToStickers = #selector(ConversationTableView.addToStickersAction(_:))
}

extension MessageItem {
    
    var allowedActions: [Selector] {
        var actions = [Selector]()
        if category.hasSuffix("_TEXT") {
            actions = [.reply, .forward, .copy, .delete]
        } else if category.hasSuffix("_STICKER") {
            actions = [.addToStickers, .reply, .forward, .delete]
        } else if category.hasSuffix("_CONTACT") {
            actions = [.reply, .forward, .delete]
        } else if category.hasSuffix("_IMAGE") {
            if mediaStatus == MediaStatus.DONE.rawValue {
                actions = [.addToStickers, .reply, .forward, .delete]
            } else {
                actions = [.reply, .delete]
            }
        } else if category.hasSuffix("_DATA") || category.hasSuffix("_VIDEO") || category.hasSuffix("_AUDIO") {
            if mediaStatus == MediaStatus.DONE.rawValue {
                actions = [.reply, .forward, .delete]
            } else {
                actions = [.reply, .delete]
            }
        } else if category == MessageCategory.SYSTEM_ACCOUNT_SNAPSHOT.rawValue || category == MessageCategory.APP_CARD.rawValue{
            actions = [.reply, .delete]
        } else {
            actions = []
        }
        if status == MessageStatus.FAILED.rawValue, let index = actions.index(of: .reply) {
            actions.remove(at: index)
        }
        return actions
    }
    
}

protocol ConversationTableViewActionDelegate: class {
    func conversationTableViewCanBecomeFirstResponder(_ tableView: ConversationTableView) -> Bool
    func conversationTableViewLongPressWillBegan(_ tableView: ConversationTableView)
    func conversationTableView(_ tableView: ConversationTableView, hasActionsforIndexPath indexPath: IndexPath) -> Bool
    func conversationTableView(_ tableView: ConversationTableView, canPerformAction action: Selector, forIndexPath indexPath: IndexPath) -> Bool
    func conversationTableView(_ tableView: ConversationTableView, didSelectAction action: ConversationTableView.Action, forIndexPath indexPath: IndexPath)
}

class ConversationTableView: UITableView {

    weak var viewController: ConversationViewController?
    weak var actionDelegate: ConversationTableViewActionDelegate?
    
    private var longPressRecognizer: UILongPressGestureRecognizer!
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    var headerViews: [ConversationDateHeaderView] {
        var headerViews = [ConversationDateHeaderView]()
        let numberOfSections = dataSource?.numberOfSections?(in: self) ?? 0
        for section in 0..<numberOfSections {
            if let headerView = headerView(forSection: section) as? ConversationDateHeaderView {
                headerViews.append(headerView)
            }
        }
        return headerViews
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        prepare()
    }
    
    override init(frame: CGRect, style: UITableViewStyle) {
        super.init(frame: frame, style: style)
        prepare()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard let indexPath = indexPathForSelectedRow, let actionDelegate = actionDelegate else {
            return false
        }
        return actionDelegate.conversationTableView(self, canPerformAction: action, forIndexPath: indexPath)
    }
    
    @objc func replyAction(_ sender: Any) {
        invokeDelegate(action: .reply)
    }
    
    @objc func forwardAction(_ sender: Any) {
        invokeDelegate(action: .forward)
    }
    
    @objc func copyAction(_ sender: Any) {
        invokeDelegate(action: .copy)
    }
    
    @objc func deleteAction(_ sender: Any) {
        invokeDelegate(action: .delete)
    }

    @objc func addToStickersAction(_ sender: Any) {
        invokeDelegate(action: .add)
    }
    
    @objc func longPressAction(_ recognizer: UIGestureRecognizer) {
        guard recognizer.state == .began, let actionDelegate = actionDelegate else {
            return
        }
        let location = recognizer.location(in: self)
        if let cell = messageCellForRow(at: location), let indexPath = indexPathForRow(at: location), actionDelegate.conversationTableView(self, hasActionsforIndexPath: indexPath)  {
            actionDelegate.conversationTableViewLongPressWillBegan(self)
            selectRow(at: indexPath, animated: true, scrollPosition: .none)
            if actionDelegate.conversationTableViewCanBecomeFirstResponder(self) {
                becomeFirstResponder()
            }
            UIMenuController.shared.setTargetRect(cell.contentFrame, in: cell)
            UIMenuController.shared.setMenuVisible(true, animated: true)
        }
    }
    
    @objc func menuControllerWillHideMenu(_ notification: Notification) {
        guard let indexPath = indexPathForSelectedRow else {
            return
        }
        deselectRow(at: indexPath, animated: true)
    }
    
    func dequeueReusableCell(withMessage message: MessageItem, for indexPath: IndexPath) -> UITableViewCell {
        if message.status == MessageStatus.FAILED.rawValue {
            return dequeueReusableCell(withReuseId: .text, for: indexPath)
        } else if message.quoteMessageId != nil {
            return dequeueReusableCell(withReuseId: .quoteText, for: indexPath)
        } else {
            return dequeueReusableCell(withReuseId: ReuseId(category: message.category), for: indexPath)
        }
    }
    
    func dequeueReusableCell(withReuseId reuseId: ReuseId, for indexPath: IndexPath) -> UITableViewCell {
        let cell = dequeueReusableCell(withIdentifier: reuseId.rawValue, for: indexPath)
        if let cell = cell as? DetailInfoMessageCell, cell.delegate == nil {
            cell.delegate = viewController
        }
        if let cell = cell as? AttachmentLoadingMessageCell, cell.attachmentLoadingDelegate == nil {
            cell.attachmentLoadingDelegate = viewController
        }
        if let cell = cell as? TextMessageCell, cell.contentLabel.delegate == nil {
            cell.contentLabel.delegate = viewController
        }
        if let cell = cell as? AppButtonGroupMessageCell, cell.appButtonDelegate == nil {
            cell.appButtonDelegate = viewController
        }
        return cell
    }

    func messageCellForRow(at point: CGPoint) -> MessageCell? {
        guard let indexPath = indexPathForRow(at: point), let cell = cellForRow(at: indexPath) as? MessageCell else {
            return nil
        }
        let converted = cell.convert(point, from: self)
        if cell.contentFrame.contains(converted) {
            return cell
        } else {
            return nil
        }
    }
    
    func scrollToBottom(animated: Bool) {
        guard contentSize.height > bounds.height else {
            return
        }
        let bottomOffset = CGPoint(x: contentOffset.x,
                                   y: contentSize.height - bounds.height + contentInset.bottom)
        setContentOffset(bottomOffset, animated: animated)
    }
    
    private func invokeDelegate(action: Action) {
        guard let indexPath = indexPathForSelectedRow else {
            return
        }
        actionDelegate?.conversationTableView(self, didSelectAction: action, forIndexPath: indexPath)
    }
    
    private func prepare() {
        register(UINib(nibName: "ConversationDateHeaderView", bundle: .main),
                 forHeaderFooterViewReuseIdentifier: ReuseId.header.rawValue)
        register(TextMessageCell.self, forCellReuseIdentifier: ReuseId.text.rawValue)
        register(PhotoMessageCell.self, forCellReuseIdentifier: ReuseId.photo.rawValue)
        register(StickerMessageCell.self, forCellReuseIdentifier: ReuseId.sticker.rawValue)
        register(UnknownMessageCell.self, forCellReuseIdentifier: ReuseId.unknown.rawValue)
        register(AppButtonGroupMessageCell.self, forCellReuseIdentifier: ReuseId.appButtonGroup.rawValue)
        register(VideoMessageCell.self, forCellReuseIdentifier: ReuseId.video.rawValue)
        register(QuoteTextMessageCell.self, forCellReuseIdentifier: ReuseId.quoteText.rawValue)
        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction(_:)))
        longPressRecognizer.delegate = TextMessageLabel.gestureRecognizerBypassingDelegateObject
        addGestureRecognizer(longPressRecognizer)
        UIMenuController.shared.menuItems = [
            UIMenuItem(title: Localized.CHAT_MESSAGE_ADD, action: #selector(addToStickersAction(_:))),
            UIMenuItem(title: Localized.CHAT_MESSAGE_MENU_REPLY, action: #selector(replyAction(_:))),
            UIMenuItem(title: Localized.CHAT_MESSAGE_MENU_FORWARD, action: #selector(forwardAction(_:))),
            UIMenuItem(title: Localized.CHAT_MESSAGE_MENU_COPY, action: #selector(copyAction(_:))),
            UIMenuItem(title: Localized.MENU_DELETE, action: #selector(deleteAction(_:)))]
        NotificationCenter.default.addObserver(self, selector: #selector(menuControllerWillHideMenu(_:)), name: .UIMenuControllerWillHideMenu, object: nil)
    }
    
}

extension ConversationTableView {
    
    enum Action {
        case reply
        case forward
        case copy
        case delete
        case add
    }
    
    enum ReuseId: String {
        case text = "TextMessageCell"
        case photo = "PhotoMessageCell"
        case sticker = "StickerMessageCell"
        case data = "DataMessageCell"
        case transfer = "TransferMessageCell"
        case system = "SystemMessageCell"
        case unknown = "UnknownMessageCell"
        case unreadHint = "UnreadHintMessageCell"
        case appButtonGroup = "AppButtonGroupCell"
        case contact = "ContactMessageCell"
        case video = "VideoMessageCell"
        case appCard = "AppCardMessageCell"
        case audio = "AudioMessageCell"
        case quoteText = "QuoteTextMessageCell"
        case header = "DateHeader"

        init(category: String) {
            if category.hasSuffix("_TEXT") {
                self = .text
            } else if category.hasSuffix("_IMAGE") {
                self = .photo
            } else if category.hasSuffix("_STICKER") {
                self = .sticker
            } else if category.hasSuffix("_DATA") {
                self = .data
            } else if category.hasSuffix("_CONTACT") {
                self = .contact
            } else if category.hasSuffix("_VIDEO") {
                self = .video
            } else if category.hasSuffix("_AUDIO") {
                self = .audio
            } else if category == MessageCategory.SYSTEM_ACCOUNT_SNAPSHOT.rawValue {
                self = .transfer
            } else if category == MessageCategory.EXT_UNREAD.rawValue {
                self = .unreadHint
            } else if category == MessageCategory.EXT_ENCRYPTION.rawValue || category == MessageCategory.SYSTEM_CONVERSATION.rawValue {
                self = .system
            } else if category == MessageCategory.APP_BUTTON_GROUP.rawValue {
                self = .appButtonGroup
            } else if category == MessageCategory.APP_CARD.rawValue {
                self = .appCard
            } else {
                self = .unknown
            }
        }
    }
    
}
