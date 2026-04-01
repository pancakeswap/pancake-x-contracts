// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwapRouter02ExecutorMultiRefactor} from "../../src/sample-executors/SwapRouter02ExecutorMultiRefactor.sol";
import {DutchOrderReactor, DutchOrder, DutchInput} from "../../src/reactors/DutchOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {MockSwapRouter} from "../util/mock/MockSwapRouter.sol";
import {SignedOrder, ResolvedOrder, OutputToken, InputToken, OrderInfo} from "../../src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISwapRouter02, ExactInputParams} from "../../src/external/ISwapRouter02.sol";
import {IReactor} from "../../src/interfaces/IReactor.sol";

contract SwapRouter02ExecutorMultiRefactorTest is Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    uint256 internal fillerPrivateKey;
    uint256 internal swapperPrivateKey;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    WETH internal weth;
    address internal filler;
    address internal swapper;
    SwapRouter02ExecutorMultiRefactor internal executor;
    MockSwapRouter internal mockSwapRouter;
    DutchOrderReactor internal reactor1;
    DutchOrderReactor internal reactor2;
    IPermit2 internal permit2;

    uint256 internal constant ONE = 10 ** 18;
    uint24 internal constant FEE = 3000;
    address internal constant PROTOCOL_FEE_OWNER = address(80085);

    event ReactorWhitelisted(address indexed reactor, bool whitelisted);

    receive() external payable {}

    function setUp() public {
        vm.warp(1000);
        vm.chainId(31337);

        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        weth = new WETH();

        fillerPrivateKey = 0x12341234;
        filler = vm.addr(fillerPrivateKey);
        swapperPrivateKey = 0x12341235;
        swapper = vm.addr(swapperPrivateKey);

        mockSwapRouter = new MockSwapRouter(address(weth));
        permit2 = IPermit2(deployPermit2());
        reactor1 = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        reactor2 = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        executor =
            new SwapRouter02ExecutorMultiRefactor(address(this), address(this), ISwapRouter02(address(mockSwapRouter)));

        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
    }

    function testSetReactorWhitelistedEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ReactorWhitelisted(address(reactor1), true);
        executor.setReactorWhitelisted(IReactor(address(reactor1)), true);

        assertTrue(executor.reactorWhitelist(address(reactor1)));
    }

    function testExecuteRevertsIfReactorNotWhitelisted() public {
        DutchOrder memory order = _buildOrder(address(reactor1), 0, ONE, ONE);
        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        bytes memory callbackData = _buildCallbackData(ONE, address(executor));

        vm.expectRevert(SwapRouter02ExecutorMultiRefactor.ReactorNotWhitelisted.selector);
        executor.execute(
            IReactor(address(reactor1)),
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            callbackData
        );
    }

    function testExecuteWithWhitelistedReactor() public {
        executor.setReactorWhitelisted(IReactor(address(reactor1)), true);

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor1)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
        });
        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        bytes memory callbackData = _buildCallbackData(ONE, address(executor));

        executor.execute(
            IReactor(address(reactor1)),
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            callbackData
        );

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), ONE / 2);
        assertEq(tokenOut.balanceOf(address(executor)), ONE / 2);
    }

    function testExecuteBatchWithWhitelistedReactor() public {
        executor.setReactorWhitelisted(IReactor(address(reactor1)), true);

        tokenIn.mint(swapper, ONE * 10);
        tokenOut.mint(address(mockSwapRouter), ONE * 10);

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        DutchOrder memory order1 = _buildOrder(address(reactor1), 0, ONE, ONE);
        DutchOrder memory order2 = _buildOrder(address(reactor1), 1, ONE * 3, ONE * 2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey, address(permit2), order2));

        bytes memory callbackData = _buildCallbackData(ONE * 4, address(executor));

        executor.executeBatch(IReactor(address(reactor1)), signedOrders, callbackData);

        assertEq(tokenOut.balanceOf(swapper), 3 ether);
        assertEq(tokenIn.balanceOf(swapper), 6 ether);
        assertEq(tokenOut.balanceOf(address(mockSwapRouter)), 6 ether);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), 4 ether);
        assertEq(tokenOut.balanceOf(address(executor)), ONE);
        assertEq(tokenIn.balanceOf(address(executor)), 0);
    }

    function testReactorCallbackRevertsIfSenderNotWhitelistedReactor() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken(address(tokenOut), ONE, swapper);
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor1)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            hex"1234",
            keccak256(abi.encode(1))
        );

        bytes memory callbackData = _buildCallbackData(ONE, address(executor));
        vm.prank(address(reactor1));
        vm.expectRevert(SwapRouter02ExecutorMultiRefactor.ReactorNotWhitelisted.selector);
        executor.reactorCallback(resolvedOrders, callbackData);
    }

    function testReactorCallbackRevertsWithoutTransientHash() public {
        executor.setReactorWhitelisted(IReactor(address(reactor2)), true);

        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken(address(tokenOut), ONE, swapper);
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor2)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            hex"1234",
            keccak256(abi.encode(2))
        );

        tokenIn.mint(address(executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        bytes memory callbackData = _buildCallbackData(ONE, address(executor));

        vm.prank(address(reactor2));
        vm.expectRevert(SwapRouter02ExecutorMultiRefactor.InvalidTransientHash.selector);
        executor.reactorCallback(resolvedOrders, callbackData);
    }

    function testNotWhitelistedCaller() public {
        executor.setReactorWhitelisted(IReactor(address(reactor1)), true);

        DutchOrder memory order = _buildOrder(address(reactor1), 0, ONE, ONE);
        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        bytes memory callbackData = _buildCallbackData(ONE, address(executor));

        vm.prank(address(0xbeef));
        vm.expectRevert(SwapRouter02ExecutorMultiRefactor.CallerNotWhitelisted.selector);
        executor.execute(
            IReactor(address(reactor1)),
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            callbackData
        );
    }

    function _buildOrder(address reactorAddr, uint256 nonce, uint256 inputAmount, uint256 outputAmount)
        internal
        view
        returns (DutchOrder memory)
    {
        return DutchOrder({
            info: OrderInfoBuilder.init(reactorAddr).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(nonce),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });
    }

    function _buildCallbackData(uint256 amountIn, address recipient) internal view returns (bytes memory) {
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);

        bytes[] memory multicallData = new bytes[](1);
        ExactInputParams memory exactInputParams = ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: recipient,
            amountIn: amountIn,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInput.selector, exactInputParams);

        return abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData);
    }
}
