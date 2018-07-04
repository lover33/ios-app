import UIKit

class MessageViewModel: CustomDebugStringConvertible {

    static let backgroundImageMargin = Margin(leading: 8, trailing: 66, top: 0, bottom: 0)
    static let bottomSeparatorHeight: CGFloat = 10

    let message: MessageItem
    let time: String
    let layoutWidth: CGFloat
    let thumbnail: UIImage?
    
    internal(set) var backgroundImage: UIImage?
    internal(set) var backgroundImageFrame = CGRect.zero
    internal(set) var cellHeight: CGFloat = 44

    internal lazy var contentMargin: Margin = {
        Margin(leading: 16, trailing: 10, top: 7, bottom: 7)
    }()
    
    public var debugDescription: String {
        return "MessageViewModel for message: \(message), layoutWidth: \(layoutWidth), cellHeight: \(cellHeight)"
    }
    
    var style: Style {
        didSet {
            if style != oldValue {
                didSetStyle()
            }
        }
    }
    
    internal var bottomSeparatorHeight: CGFloat {
        if style.contains(.hasBottomSeparator) {
            return MessageViewModel.bottomSeparatorHeight
        } else {
            return 0
        }
    }
    
    init(message: MessageItem, style: Style, fits layoutWidth: CGFloat) {
        self.message = message
        self.style = style
        self.time = message.createdAt.toUTCDate().timeHoursAndMinutes()
        self.layoutWidth = layoutWidth
        if let thumbImage = message.thumbImage, let imageData = Data(base64Encoded: thumbImage)  {
            thumbnail = UIImage(data: imageData)
        } else {
            thumbnail = nil
        }
        didSetStyle()
    }
    
    func didSetStyle() {
        
    }

}

extension MessageViewModel {
    
    struct Style: OptionSet {
        let rawValue: Int
        static let received = Style(rawValue: 1 << 0)
        static let sent = Style(rawValue: 1 << 1)
        static let hasTail = Style(rawValue: 1 << 2)
        static let hasBottomSeparator = Style(rawValue: 1 << 3)
        static let showFullname = Style(rawValue: 1 << 4)
    }
    
    struct Margin {
        let leading: CGFloat
        let trailing: CGFloat
        let top: CGFloat
        let bottom: CGFloat
        let horizontal: CGFloat
        let vertical: CGFloat
        
        init(leading: CGFloat, trailing: CGFloat, top: CGFloat, bottom: CGFloat) {
            self.leading = leading
            self.trailing = trailing
            self.top = top
            self.bottom = bottom
            self.horizontal = leading + trailing
            self.vertical = top + bottom
        }
    }
    
}
