// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";

/// @notice A fill contract that uses SwapRouter02 to execute trades; supports multiple whitelisted reactors
contract SwapRouter02ExecutorMultiRefactor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice thrown if reactorCallback is called with a non-whitelisted filler
    error CallerNotWhitelisted();
    /// @notice thrown if the reactor is not whitelisted
    error ReactorNotWhitelisted();
    /// @notice thrown if callback is not tied to the latest execute/executeBatch transient hash
    error InvalidTransientHash();

    ISwapRouter02 private immutable swapRouter02;
    address private immutable whitelistedCaller;
    WETH private immutable weth;

    /// @dev uint256 internal constant TRANSIENT_CALLBACK_HASH_SLOT =
    /// uint256(keccak256("SwapRouter02ExecutorMultiRefactor.transientHash")) - 1;
    uint256 internal constant TRANSIENT_CALLBACK_HASH_SLOT =
        0x2f0bac3a76a2fba8f3f4772f250e00386eb67437599f5c1bacd6b53f5ec962e8;

    /// @notice reactors allowed to call reactorCallback and to be used in execute / executeBatch
    mapping(address => bool) public reactorWhitelist;
    /// @notice Emitted when owner updates reactor whitelist status
    event ReactorWhitelisted(address indexed reactor, bool whitelisted);

    modifier onlyWhitelistedCaller() {
        if (msg.sender != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        _;
    }

    /// @dev reactor must be a whitelisted reactor address
    modifier onlyReactor(address reactor) {
        if (!reactorWhitelist[reactor]) {
            revert ReactorNotWhitelisted();
        }
        _;
    }

    constructor(address _whitelistedCaller, address _owner, ISwapRouter02 _swapRouter02) Owned(_owner) {
        whitelistedCaller = _whitelistedCaller;
        swapRouter02 = _swapRouter02;
        weth = WETH(payable(_swapRouter02.WETH9()));
    }

    /// @notice Add or remove a reactor from the whitelist (only owner)
    function setReactorWhitelisted(IReactor reactor, bool whitelisted) external onlyOwner {
        reactorWhitelist[address(reactor)] = whitelisted;
        emit ReactorWhitelisted(address(reactor), whitelisted);
    }

    /// @notice assume that we already have all output tokens
    function execute(IReactor reactor, SignedOrder calldata order, bytes calldata callbackData)
        external
        onlyWhitelistedCaller
        onlyReactor(address(reactor))
    {
        _saveTransientHash(keccak256(abi.encode(address(reactor), callbackData)));
        reactor.executeWithCallback(order, callbackData);
    }

    /// @notice assume that we already have all output tokens
    function executeBatch(IReactor reactor, SignedOrder[] calldata orders, bytes calldata callbackData)
        external
        onlyWhitelistedCaller
        onlyReactor(address(reactor))
    {
        _saveTransientHash(keccak256(abi.encode(address(reactor), callbackData)));
        reactor.executeBatchWithCallback(orders, callbackData);
    }

    /// @notice fill UniswapX orders using SwapRouter02
    /// @param callbackData It has the below encoded:
    /// address[] memory tokensToApproveForSwapRouter02: Max approve these tokens to swapRouter02
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor (msg.sender)
    /// bytes[] memory multicallData: Pass into swapRouter02.multicall()
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external onlyReactor(msg.sender) {
        if (_loadTransientHash() != keccak256(abi.encode(msg.sender, callbackData))) {
            revert InvalidTransientHash();
        }
        // Clear transient hash before external interactions.
        _saveTransientHash(bytes32(0));

        (
            address[] memory tokensToApproveForSwapRouter02,
            address[] memory tokensToApproveForReactor,
            bytes[] memory multicallData
        ) = abi.decode(callbackData, (address[], address[], bytes[]));

        address reactorAddr = msg.sender;

        unchecked {
            for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
                ERC20(tokensToApproveForSwapRouter02[i]).safeApprove(address(swapRouter02), type(uint256).max);
            }

            for (uint256 i = 0; i < tokensToApproveForReactor.length; i++) {
                ERC20(tokensToApproveForReactor[i]).safeApprove(reactorAddr, type(uint256).max);
            }
        }

        swapRouter02.multicall(type(uint256).max, multicallData);

        // transfer any native balance to the reactor
        // it will refund any excess
        if (address(this).balance > 0) {
            CurrencyLibrary.transferNative(reactorAddr, address(this).balance);
        }
    }

    /// @notice This function can be used to convert ERC20s to ETH that remains in this contract
    /// @param tokensToApprove Max approve these tokens to swapRouter02
    /// @param multicallData Pass into swapRouter02.multicall()
    function multicall(ERC20[] calldata tokensToApprove, bytes[] calldata multicallData) external onlyOwner {
        for (uint256 i = 0; i < tokensToApprove.length; i++) {
            tokensToApprove[i].safeApprove(address(swapRouter02), type(uint256).max);
        }
        swapRouter02.multicall(type(uint256).max, multicallData);
    }

    /// @notice Unwraps the contract's WETH9 balance and sends it to the recipient as ETH. Can only be called by owner.
    /// @param recipient The address receiving ETH
    function unwrapWETH(address recipient) external onlyOwner {
        uint256 balanceWETH = weth.balanceOf(address(this));

        weth.withdraw(balanceWETH);
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Necessary for this contract to receive ETH when calling unwrapWETH()
    receive() external payable {}

    function _saveTransientHash(bytes32 hash) internal {
        assembly ("memory-safe") {
            tstore(TRANSIENT_CALLBACK_HASH_SLOT, hash)
        }
    }

    function _loadTransientHash() internal view returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := tload(TRANSIENT_CALLBACK_HASH_SLOT)
        }
    }
}
