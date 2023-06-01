import Foundation
import RxSwift
import RxRelay
import TronKit
import HdWalletKit
import MarketKit

class TronKitManager {
    let network: TronKit.Network
    private let disposeBag = DisposeBag()

    private weak var _tronKitWrapper: TronKitWrapper?

    private let tronKitCreatedRelay = PublishRelay<Void>()
    private var currentAccount: Account?

    private let queue = DispatchQueue(label: "io.horizontalsystems.unstoppable.tron-kit-manager", qos: .userInitiated)

    init(network: TronKit.Network) {
        self.network = network
    }

    private func _tronKitWrapper(account: Account, blockchainType: BlockchainType) throws -> TronKitWrapper {
        if let _tronKitWrapper = _tronKitWrapper, let currentAccount = currentAccount, currentAccount == account {
            return _tronKitWrapper
        }

        let address: TronKit.Address
        var signer: Signer?

        switch account.type {
            case .mnemonic:
                guard let seed = account.type.mnemonicSeed else {
                    throw KitWrapperError.mnemonicNoSeed
                }
                address = try Signer.address(seed: seed)
                signer = try Signer.instance(seed: seed)
            default:
                throw AdapterError.unsupportedAccount
        }

        let tronKit = try TronKit.Kit.instance(
            address: address,
            network: network,
            walletId: account.id,
            minLogLevel: .verbose
        )

        tronKit.start()

        let wrapper = TronKitWrapper(blockchainType: blockchainType, tronKit: tronKit, signer: signer)

        _tronKitWrapper = wrapper
        currentAccount = account

        tronKitCreatedRelay.accept(())

        return wrapper
    }

}

extension TronKitManager {

    var tronKitCreatedObservable: Observable<Void> {
        tronKitCreatedRelay.asObservable()
    }

    var tronKitWrapper: TronKitWrapper? {
        queue.sync {
            _tronKitWrapper
        }
    }

    func tronKitWrapper(account: Account, blockchainType: BlockchainType) throws -> TronKitWrapper {
        try queue.sync {
            try _tronKitWrapper(account: account, blockchainType: blockchainType)
        }
    }

}

class TronKitWrapper {
    let blockchainType: BlockchainType
    let tronKit: TronKit.Kit
    let signer: Signer?

    init(blockchainType: BlockchainType, tronKit: TronKit.Kit, signer: Signer?) {
        self.blockchainType = blockchainType
        self.tronKit = tronKit
        self.signer = signer
    }

    func sendSingle(contract: Contract, feeLimit: Int?) -> Single<Void> {
        guard let signer = signer else {
            return Single.error(SignerError.signerNotSupported)
        }

        return Single<Void>.create { [weak self] observer in
            guard let strongSelf = self else {
                observer(.error(TronKitManager.KitWrapperError.disposeError))
                return Disposables.create()
            }

            let task = Task {
                do {
                    try await strongSelf.tronKit.send(contract: contract, signer: signer, feeLimit: feeLimit)
                    observer(.success(()))
                } catch {
                    observer(.error(error))
                }
            }

            return Disposables.create {
                task.cancel()
            }
        }
    }

}

extension TronKitManager {

    enum KitWrapperError: Error {
        case disposeError
        case mnemonicNoSeed
    }

}

extension TronKitWrapper {

    enum SignerError: Error {
        case signerNotSupported
    }

}