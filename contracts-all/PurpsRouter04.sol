// SPDX-License-Identifier: MIT
// Wrapper for IRouter02 to add interface fees and referrals
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Address.sol";

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

contract PurpsRouter04 {
    using Address for address payable;

    struct RewardInfo {
        uint256 totalReward;
        uint256 availableReward;
    }

    event ReferralFeeClaimed(
        address indexed referrer,
        address indexed token,
        uint amount
    );

    error NotAuthorized();
    error InvalidReferrer();

    uint public constant DENOMINATOR = 10_000;
    address public constant WETH = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    uint public fee;
    uint public referralFee; // bps of regular fee
    address public feeRecipient;

    mapping(address => address) public referrerOf;
    mapping(address => uint) public referralsCountOf;
    mapping(address => address[]) public rewardTokensOf; // referrer => tokens array
    mapping(address => mapping(address => RewardInfo)) public referralRewardsOf; // referrer => token => rewards
    mapping(address => mapping(address => bool)) private hasRewardToken; // referrer => token => exists

    IRouter02 constant SWAP_ROUTER =
        IRouter02(0xc80585f78A6e44fb46e1445006f820448840386e);

    constructor(uint _fee, uint _referralFee, address _feeRecipient) {
        fee = _fee;
        referralFee = _referralFee;
        feeRecipient = _feeRecipient;
    }

    // Internal utility functions

    /**
     * @dev Processes referral fee and updates referrer rewards
     * @param feeAmount The total fee amount to process
     * @param token The token address for the reward (use WETH for ETH)
     * @return remainingFee The fee amount after deducting referral portion
     */
    function _processReferralFee(
        uint feeAmount,
        address token
    ) internal returns (uint remainingFee) {
        address referrer = referrerOf[tx.origin]; // use tx.origin to support other wrappers and ensure correct referrer
        if (referrer != address(0)) {
            uint referralFeeAmount = (feeAmount * referralFee) / DENOMINATOR;
            if (!hasRewardToken[referrer][token]) {
                rewardTokensOf[referrer].push(token);
                hasRewardToken[referrer][token] = true;
            }
            referralRewardsOf[referrer][token].totalReward += referralFeeAmount;
            referralRewardsOf[referrer][token]
                .availableReward += referralFeeAmount;
            return feeAmount - referralFeeAmount;
        }
        return feeAmount;
    }

    // Swap functions

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        // Handle fee on the amountIn
        uint amountIn = msg.value;
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        amountIn -= feeAmount;
        feeAmount = _processReferralFee(feeAmount, WETH);
        payable(feeRecipient).sendValue(feeAmount);

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
        IERC20 inputToken = IERC20(path[0]);
        inputToken.transferFrom(msg.sender, address(this), amountIn);
        inputToken.approve(address(SWAP_ROUTER), amountIn);

        // Handle fee on the amountIn
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        amountIn -= feeAmount;
        feeAmount = _processReferralFee(feeAmount, path[0]);
        inputToken.transfer(feeRecipient, feeAmount);

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
        amounts[0] += feeAmount;
        feeAmount = _processReferralFee(feeAmount, WETH);
        payable(feeRecipient).sendValue(feeAmount);

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
        IERC20 inputToken = IERC20(path[0]);
        inputToken.transferFrom(msg.sender, address(this), amountIn);
        inputToken.approve(address(SWAP_ROUTER), amountIn);

        // Handle fee on the amountIn
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        amountIn -= feeAmount;
        feeAmount = _processReferralFee(feeAmount, path[0]);
        inputToken.transfer(feeRecipient, feeAmount);

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
        IERC20 inputToken = IERC20(path[0]);
        inputToken.transferFrom(msg.sender, address(this), amountInMax);
        inputToken.approve(address(SWAP_ROUTER), amountInMax);

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
        amounts[0] += feeAmount;
        feeAmount = _processReferralFee(feeAmount, path[0]);
        inputToken.transfer(feeRecipient, feeAmount);

        // Refund any unused tokens to user
        uint unusedAmount = amountInMax - amounts[0];
        if (unusedAmount > 0) {
            inputToken.transfer(msg.sender, unusedAmount);
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
        IERC20 inputToken = IERC20(path[0]);
        inputToken.transferFrom(msg.sender, address(this), amountInMax);
        inputToken.approve(address(SWAP_ROUTER), amountInMax);

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
        amounts[0] += feeAmount;
        feeAmount = _processReferralFee(feeAmount, path[0]);
        inputToken.transfer(feeRecipient, feeAmount);

        // Refund any unused tokens to user
        uint unusedAmount = amountInMax - amounts[0];
        if (unusedAmount > 0) {
            inputToken.transfer(msg.sender, unusedAmount);
        }
    }

    // Referral functions

    function setReferrer(address referrer) external {
        if (referrer == address(0)) revert InvalidReferrer();
        if (referrerOf[msg.sender] != address(0)) revert InvalidReferrer();
        referrerOf[msg.sender] = referrer;
        referralsCountOf[referrer]++;
    }

    function claimAllRewards() external {
        address[] storage tokens = rewardTokensOf[msg.sender];
        uint256 length = tokens.length;

        for (uint256 i = 0; i < length; i++) {
            address token = tokens[i];
            uint256 amount = referralRewardsOf[msg.sender][token]
                .availableReward;

            if (amount > 0) {
                referralRewardsOf[msg.sender][token].availableReward = 0;

                if (token == WETH) {
                    payable(msg.sender).sendValue(amount);
                } else {
                    IERC20(token).transfer(msg.sender, amount);
                }

                emit ReferralFeeClaimed(msg.sender, token, amount);
            }
        }
    }

    function claimReward(address token) external {
        uint256 amount = referralRewardsOf[msg.sender][token].availableReward;
        if (amount > 0) {
            referralRewardsOf[msg.sender][token].availableReward = 0;
            if (token == WETH) {
                payable(msg.sender).sendValue(amount);
            } else {
                IERC20(token).transfer(msg.sender, amount);
            }
        }

        emit ReferralFeeClaimed(msg.sender, token, amount);
    }

    function getReferralRewards(
        address referrer
    )
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory totalRewards,
            uint256[] memory availableRewards
        )
    {
        tokens = rewardTokensOf[referrer];
        uint256 length = tokens.length;

        totalRewards = new uint256[](length);
        availableRewards = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            totalRewards[i] = referralRewardsOf[referrer][tokens[i]]
                .totalReward;
            availableRewards[i] = referralRewardsOf[referrer][tokens[i]]
                .availableReward;
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

    function setReferralFee(uint _referralFee) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        referralFee = _referralFee;
    }

    receive() external payable {}
}
