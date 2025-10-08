// SPDX-License-Identifier: MIT
// Wrapper for the Router02 which adds an interface fee to swaps.
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRouter02 {
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IERC20 {
    function transfer(address to, uint amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint amount
    ) external returns (bool);

    function approve(address spender, uint amount) external returns (bool);
}

error NotAuthorized();

contract PurpsRouter03 {
    using Address for address payable;

    uint public constant DENOMINATOR = 10_000;
    uint public fee;
    address public feeRecipient;

    IRouter02 constant SWAP_ROUTER =
        IRouter02(0xc80585f78A6e44fb46e1445006f820448840386e);

    constructor(uint _fee, address _feeRecipient) {
        fee = _fee;
        feeRecipient = _feeRecipient;
    }

    // Swap functions

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        // Handle fee
        uint amountIn = msg.value;
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        payable(feeRecipient).sendValue(feeAmount);
        amountIn -= feeAmount;

        // Perform regular swap
        amounts = SWAP_ROUTER.swapExactETHForTokens{value: amountIn}(
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        // Transfer to this and approve router to spend tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).approve(address(SWAP_ROUTER), amountIn);

        // Handle fee
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        IERC20(path[0]).transfer(feeRecipient, feeAmount);
        amountIn -= feeAmount;

        // Perform regular swap
        amounts = SWAP_ROUTER.swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        // Perform regular swap
        amounts = SWAP_ROUTER.swapETHForExactTokens{value: msg.value}(
            amountOut,
            path,
            to,
            deadline
        );

        // Calculate and transfer fee from the amount actually used (amounts[0])
        uint feeAmount = (amounts[0] * fee) / DENOMINATOR;
        payable(feeRecipient).sendValue(feeAmount);
        amounts[0] += feeAmount;

        // Refund remaining ETH if any
        if (msg.value > amounts[0]) {
            payable(msg.sender).sendValue(msg.value - amounts[0]);
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        // Transfer to this and approve router to spend tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).approve(address(SWAP_ROUTER), amountIn);

        // Handle fee
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        IERC20(path[0]).transfer(feeRecipient, feeAmount);
        amountIn -= feeAmount;

        // Perform regular swap
        amounts = SWAP_ROUTER.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        // Transfer to this and approve router to spend tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountInMax);
        IERC20(path[0]).approve(address(SWAP_ROUTER), amountInMax);

        // Perform regular swap
        amounts = SWAP_ROUTER.swapTokensForExactETH(
            amountOut,
            amountInMax,
            path,
            to,
            deadline
        );

        // Calculate and transfer fee from the amount actually used (amounts[0])
        uint feeAmount = (amounts[0] * fee) / DENOMINATOR;
        IERC20(path[0]).transfer(feeRecipient, feeAmount);
        amounts[0] += feeAmount;

        // Refund any unused tokens to user
        uint unusedAmount = amountInMax - amounts[0];
        if (unusedAmount > 0) {
            IERC20(path[0]).transfer(msg.sender, unusedAmount);
        }
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        // Transfer to this and approve router to spend tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountInMax);
        IERC20(path[0]).approve(address(SWAP_ROUTER), amountInMax);

        // Perform regular swap
        amounts = SWAP_ROUTER.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            to,
            deadline
        );

        // Calculate and transfer fee from the amount actually used (amounts[0])
        uint feeAmount = (amounts[0] * fee) / DENOMINATOR;
        IERC20(path[0]).transfer(feeRecipient, feeAmount);
        amounts[0] += feeAmount;

        // Refund any unused tokens to user
        uint unusedAmount = amountInMax - amounts[0];
        if (unusedAmount > 0) {
            IERC20(path[0]).transfer(msg.sender, unusedAmount);
        }
    }

    // Admin functions

    function setFeeRecipient(address _feeRecipient) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        feeRecipient = _feeRecipient;
    }

    function setFee(uint _fee) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        fee = _fee;
    }

    receive() external payable {}
}
