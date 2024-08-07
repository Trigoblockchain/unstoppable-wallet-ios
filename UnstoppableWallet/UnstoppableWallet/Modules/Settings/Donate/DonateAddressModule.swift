import UIKit

enum DonateAddressModule {
    static var viewController: UIViewController {
        let viewModel = DonateAddressViewModel(marketKit: App.shared.marketKit)
        return DonateAddressViewController(viewModel: viewModel)
    }
}
