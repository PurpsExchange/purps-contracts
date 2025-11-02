// SPDX-License-Identifier: MIT
// Wrapper for IRouter02 to add interface fees and referrals
pragma solidity ^0.8.30;

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

    event FeeRecipientSet(address indexed newFeeRecipient);
    event FeeSet(uint newFee);
    event ReferralFeeSet(address indexed referrer, uint newReferralFee);
    event ReferrerSet(address indexed referrer, address indexed user);

    error NotAuthorized();
    error InvalidReferrer();

    uint public constant DENOMINATOR = 10_000;
    address public constant WETH = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;

    address public feeRecipient;
    uint public fee;
    uint public referralFee; // bps of regular fee
    mapping(address => uint) public referralFeeOf; // custom referral fees

    mapping(address => address) public referrerOf;
    mapping(address => uint) public referralsCountOf;
    mapping(address => address[]) public rewardTokensOf; // referrer => tokens array
    mapping(address => mapping(address => RewardInfo)) public referralRewardsOf; // referrer => token => rewards
    mapping(address => mapping(address => bool)) private hasRewardToken; // referrer => token => exists

    IRouter02 constant SWAP_ROUTER =
        IRouter02(0x22aDf91b491abc7a50895Cd5c5c194EcCC93f5E2);

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
        if (referralFee == 0) {
            // referral fee is disabled globally
            return feeAmount;
        }

        address referrer = referrerOf[tx.origin]; // use tx.origin to support other wrappers and ensure correct referrer
        if (referrer != address(0)) {
            uint _referralFee = referralFeeOf[referrer];
            if (_referralFee == 0) {
                _referralFee = referralFee;
            }

            uint referralFeeAmount = (feeAmount * _referralFee) / DENOMINATOR;
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
        uint originalAmountIn = msg.value;
        uint amountIn = originalAmountIn;
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        amountIn -= feeAmount;
        feeAmount = _processReferralFee(feeAmount, WETH);
        if (feeAmount > 0) {
            payable(feeRecipient).sendValue(feeAmount);
        }

        // Adjust amountOutMin proportionally to account for reduced input
        uint adjustedAmountOutMin = (amountOutMin * amountIn) /
            originalAmountIn;

        // Perform regular swap
        amounts = SWAP_ROUTER.swapExactETHForTokens{value: amountIn}(
            adjustedAmountOutMin,
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
        uint originalAmountIn = amountIn;
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        amountIn -= feeAmount;
        feeAmount = _processReferralFee(feeAmount, path[0]);
        if (feeAmount > 0) {
            inputToken.transfer(feeRecipient, feeAmount);
        }

        // Adjust amountOutMin proportionally to account for reduced input
        uint adjustedAmountOutMin = (amountOutMin * amountIn) /
            originalAmountIn;

        // Perform regular swap
        amounts = SWAP_ROUTER.swapExactTokensForETH(
            amountIn,
            adjustedAmountOutMin,
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
        // Calculate and deduct fee before the swap
        uint feeAmount = (msg.value * fee) / DENOMINATOR;
        uint valueForSwap = msg.value - feeAmount;

        // Process referral fee and send to fee recipient
        feeAmount = _processReferralFee(feeAmount, WETH);
        if (feeAmount > 0) {
            payable(feeRecipient).sendValue(feeAmount);
        }

        // Perform swap with remaining value
        amounts = SWAP_ROUTER.swapETHForExactTokens{value: valueForSwap}(
            amountOut,
            path,
            to,
            deadline
        );

        // Refund any unused ETH from the swap
        uint unusedAmount = valueForSwap - amounts[0];
        if (unusedAmount > 0) {
            payable(msg.sender).sendValue(unusedAmount);
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
        uint originalAmountIn = amountIn;
        uint feeAmount = (amountIn * fee) / DENOMINATOR;
        amountIn -= feeAmount;
        feeAmount = _processReferralFee(feeAmount, path[0]);
        if (feeAmount > 0) {
            inputToken.transfer(feeRecipient, feeAmount);
        }

        // Adjust amountOutMin proportionally to account for reduced input
        uint adjustedAmountOutMin = (amountOutMin * amountIn) /
            originalAmountIn;

        // Perform regular swap
        amounts = SWAP_ROUTER.swapExactTokensForTokens(
            amountIn,
            adjustedAmountOutMin,
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
        uint actualTokensReceived = inputToken.balanceOf(address(this)); // support FOT tokens

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

        // Refund any unused tokens to user before processing referral fee
        uint unusedAmount = actualTokensReceived - amounts[0] - feeAmount;
        if (unusedAmount > 0) {
            inputToken.transfer(msg.sender, unusedAmount);
        }

        // Process referral fee and send to fee recipient
        feeAmount = _processReferralFee(feeAmount, path[0]);
        if (feeAmount > 0) {
            inputToken.transfer(feeRecipient, feeAmount);
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
        uint actualTokensReceived = inputToken.balanceOf(address(this)); // support FOT tokens

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

        // Refund any unused tokens to user before processing referral fee
        uint unusedAmount = actualTokensReceived - amounts[0] - feeAmount;
        if (unusedAmount > 0) {
            inputToken.transfer(msg.sender, unusedAmount);
        }

        // Process referral fee and send to fee recipient
        feeAmount = _processReferralFee(feeAmount, path[0]);
        if (feeAmount > 0) {
            inputToken.transfer(feeRecipient, feeAmount);
        }
    }

    // Referral functions

    function setReferrer(address referrer) external {
        if (referrer == address(0)) revert InvalidReferrer();
        if (referrer == msg.sender) revert InvalidReferrer();
        if (referrerOf[msg.sender] != address(0)) revert InvalidReferrer();
        referrerOf[msg.sender] = referrer;
        referralsCountOf[referrer]++;
        emit ReferrerSet(referrer, msg.sender);
    }

    /**
     * @dev Claims rewards for a batch of tokens to avoid gas limits
     * @param startIndex Starting index in the reward tokens array (inclusive)
     * @param endIndex Ending index in the reward tokens array (exclusive)
     */
    function claimRewardsBatch(uint256 startIndex, uint256 endIndex) external {
        address[] storage tokens = rewardTokensOf[msg.sender];
        uint256 length = tokens.length;

        require(startIndex < length, "Start index out of bounds");
        require(endIndex <= length, "End index out of bounds");
        require(startIndex < endIndex, "Invalid range");

        for (uint256 i = startIndex; i < endIndex; i++) {
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

    /**
     * @dev Claims all rewards at once. WARNING: May fail for users with many reward tokens due to gas limits.
     * Consider using claimRewardsBatch() for large numbers of tokens.
     */
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

    /**
     * @dev Claims a single reward token
     * @param token The token address to claim
     */
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

    /**
     * @dev Returns the referral rewards for a referrer
     * @param referrer The referrer address to check
     * @return tokens The tokens with rewards
     * @return totalRewards The total rewards for each token
     * @return availableRewards The available rewards for each token
     */
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

    /**
     * @dev Returns the number of reward tokens for a referrer
     * @param referrer The referrer address to check
     * @return count The number of different tokens with rewards
     */
    function getRewardTokenCount(
        address referrer
    ) external view returns (uint256 count) {
        return rewardTokensOf[referrer].length;
    }

    // Admin functions

    function setFeeRecipient(address _feeRecipient) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        feeRecipient = _feeRecipient;
        emit FeeRecipientSet(_feeRecipient);
    }

    function setFee(uint _fee) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        require(_fee <= 500, "Max 5% fee");
        fee = _fee;
        emit FeeSet(_fee);
    }

    function setReferralFee(uint _referralFee) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        require(_referralFee <= DENOMINATOR, "Max 100% referral fee");
        referralFee = _referralFee;
        emit ReferralFeeSet(address(0), _referralFee);
    }

    function setReferralFeeOf(address referrer, uint _referralFee) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        require(_referralFee <= DENOMINATOR, "Max 100% referral fee");
        referralFeeOf[referrer] = _referralFee;
        emit ReferralFeeSet(referrer, _referralFee);
    }

    receive() external payable {}
}
