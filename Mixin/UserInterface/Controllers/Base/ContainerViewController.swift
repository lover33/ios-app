import UIKit

extension UIViewController {
    
    var container: ContainerViewController? {
        return parent as? ContainerViewController
    }

}

protocol ContainerViewControllerDelegate: class {

    func barLeftButtonTappedAction()

    func barRightButtonTappedAction()

    func prepareBar(rightButton: StateResponsiveButton)

    func textBarRightButton() -> String?

    func imageBarRightButton() -> UIImage?
}

extension ContainerViewControllerDelegate where Self: UIViewController {

    func prepareBar(rightButton: StateResponsiveButton) {

    }

    func textBarRightButton() -> String? {
        return nil
    }

    func imageBarRightButton() -> UIImage? {
        return nil
    }

    func barLeftButtonTappedAction() {
        navigationController?.popViewController(animated: true)
    }

    func barRightButtonTappedAction() {
        
    }

}

class ContainerViewController: UIViewController {

    @IBOutlet weak var navigationBar: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var rightButton: StateResponsiveButton!
    @IBOutlet weak var leftButton: UIButton!
    
    @IBOutlet weak var rightButtonTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var rightButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var rightbuttonHeightConstraint: NSLayoutConstraint!

    fileprivate weak var delegate: ContainerViewControllerDelegate?
    fileprivate(set) var viewController: UIViewController!
    fileprivate var controllerTitle = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        prepareBarRightButton()
        navigationBar.layoutIfNeeded()
        titleLabel.text = controllerTitle
        addChildViewController(viewController)
        containerView.addSubview(viewController.view)
        viewController.view.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        viewController.didMove(toParentViewController: self)
    }

    @IBAction func rightAction(_ sender: Any) {
        delegate?.barRightButtonTappedAction()
    }

    private func prepareBarRightButton() {
        guard let delegate = self.delegate else {
            rightButtonWidthConstraint.priority = .defaultLow
            return
        }

        if let text = delegate.textBarRightButton() {
            rightButton.setTitle(text, for: .normal)
            rightButton.enabledColor = .clear
            rightButton.disabledColor = .clear
            rightButton.isEnabled = false
            rightButton.setTitleColor(.lightGray, for: .disabled)
            rightButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
            rightButtonWidthConstraint.priority = .defaultLow
        } else if let image = delegate.imageBarRightButton() {
            rightButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            rightButton.setImage(image, for: .normal)
        }
        delegate.prepareBar(rightButton: rightButton)
        rightButton.saveNormalState()
    }

    @IBAction func backAction(_ sender: Any) {
        guard let delegate = self.delegate else {
            navigationController?.popViewController(animated: true)
            return
        }
        delegate.barLeftButtonTappedAction()
    }

    class func instance(viewController: UIViewController, title: String) -> UIViewController {
        let vc = Storyboard.common.instantiateInitialViewController() as! ContainerViewController
        vc.viewController = viewController
        vc.delegate = viewController as? ContainerViewControllerDelegate
        vc.controllerTitle = title
        return vc
    }

}
