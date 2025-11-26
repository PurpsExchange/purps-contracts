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
    event ReferralFeeLevelSet(uint8 level, uint newFee);
    event ReferrerSet(address indexed referrer, address indexed user);

    error NotAuthorized();
    error InvalidReferrer();
    error ReferralCycleDetected();

    uint public constant DENOMINATOR = 10_000;
    address public constant WETH = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;

    address public feeRecipient;
    uint public fee;
    uint public referralFee; // bps of regular fee (level 1)
    uint public referralFeeLvl2; // bps of regular fee (level 2)
    uint public referralFeeLvl3; // bps of regular fee (level 3)
    mapping(address => uint) public referralFeeOf; // custom referral fees for level 1

    mapping(address => address) public referrerOf;
    mapping(address => uint) public referralsCountOf;
    mapping(address => address[]) public rewardTokensOf; // referrer => tokens array
    mapping(address => mapping(address => RewardInfo)) public referralRewardsOf; // referrer => token => rewards
    mapping(address => mapping(address => bool)) private hasRewardToken; // referrer => token => exists

    IRouter02 constant SWAP_ROUTER =
        IRouter02(0x22aDf91b491abc7a50895Cd5c5c194EcCC93f5E2);

    constructor(
        uint _fee,
        uint _referralFee,
        uint _referralFeeLvl2,
        uint _referralFeeLvl3,
        address _feeRecipient
    ) {
        fee = _fee;
        referralFee = _referralFee;
        referralFeeLvl2 = _referralFeeLvl2;
        referralFeeLvl3 = _referralFeeLvl3;
        feeRecipient = _feeRecipient;
    }

    // Internal utility functions

    /**
     * @dev Adds reward to a referrer's balance for a specific token
     * @param referrer The referrer address to credit
     * @param token The token address for the reward (use WETH for ETH)
     * @param amount The amount to add
     */
    function _addReward(address referrer, address token, uint amount) internal {
        if (!hasRewardToken[referrer][token]) {
            rewardTokensOf[referrer].push(token);
            hasRewardToken[referrer][token] = true;
        }
        referralRewardsOf[referrer][token].totalReward += amount;
        referralRewardsOf[referrer][token].availableReward += amount;
    }

    /**
     * @dev Processes referral fee and updates referrer rewards across 3 levels
     * @param feeAmount The total fee amount to process
     * @param token The token address for the reward (use WETH for ETH)
     * @return remainingFee The fee amount after deducting referral portions
     */
    function _processReferralFee(
        uint feeAmount,
        address token
    ) internal returns (uint remainingFee) {
        if (referralFee == 0) {
            // referral fee disabled globally
            return feeAmount;
        }

        uint totalReferralFees;

        // Level 1 Referrer
        address level1 = referrerOf[tx.origin]; // use tx.origin to support other wrappers and ensure correct referrer
        if (level1 != address(0)) {
            uint _referralFee = referralFeeOf[level1];
            if (_referralFee == 0) {
                _referralFee = referralFee;
            }

            unchecked {
                // Safe: fee percentages are capped at 100% (DENOMINATOR), result <= feeAmount
                uint level1FeeAmount = (feeAmount * _referralFee) / DENOMINATOR;
                _addReward(level1, token, level1FeeAmount);
                totalReferralFees += level1FeeAmount;

                if (referralFeeLvl2 > 0) {
                    // Level 2 Referrer
                    address level2 = referrerOf[level1];
                    if (level2 != address(0)) {
                        // Safe: referralFeeLvl2 is capped at DENOMINATOR
                        uint level2FeeAmount = (feeAmount * referralFeeLvl2) /
                            DENOMINATOR;
                        _addReward(level2, token, level2FeeAmount);
                        totalReferralFees += level2FeeAmount;

                        // Level 3 Referrer
                        if (referralFeeLvl3 > 0) {
                            address level3 = referrerOf[level2];
                            if (level3 != address(0)) {
                                // Safe: referralFeeLvl3 is capped at DENOMINATOR
                                uint level3FeeAmount = (feeAmount *
                                    referralFeeLvl3) / DENOMINATOR;
                                _addReward(level3, token, level3FeeAmount);
                                totalReferralFees += level3FeeAmount;
                            }
                        }
                    }
                }
            }
        }

        unchecked {
            // Safe: totalReferralFees is sum of percentages of feeAmount, always <= feeAmount
            return feeAmount - totalReferralFees;
        }
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
        uint amountIn;
        uint feeAmount;

        unchecked {
            // Safe: fee is capped at 5% (500/10000), so feeAmount < originalAmountIn
            feeAmount = (originalAmountIn * fee) / DENOMINATOR;
            amountIn = originalAmountIn - feeAmount;
        }

        feeAmount = _processReferralFee(feeAmount, WETH);
        if (feeAmount > 0) {
            payable(feeRecipient).sendValue(feeAmount);
        }

        // Adjust amountOutMin proportionally to account for reduced input
        uint adjustedAmountOutMin;
        unchecked {
            // Safe: amountIn < originalAmountIn, so result <= amountOutMin
            adjustedAmountOutMin = (amountOutMin * amountIn) / originalAmountIn;
        }

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
        uint feeAmount;

        unchecked {
            // Safe: fee is capped at 5% (500/10000)
            feeAmount = (amountIn * fee) / DENOMINATOR;
            amountIn -= feeAmount;
        }

        feeAmount = _processReferralFee(feeAmount, path[0]);
        if (feeAmount > 0) {
            inputToken.transfer(feeRecipient, feeAmount);
        }

        // Adjust amountOutMin proportionally to account for reduced input
        uint adjustedAmountOutMin;
        unchecked {
            // Safe: amountIn < originalAmountIn
            adjustedAmountOutMin = (amountOutMin * amountIn) / originalAmountIn;
        }

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
        uint feeAmount;
        uint valueForSwap;

        unchecked {
            // Safe: fee is capped at 5% (500/10000)
            feeAmount = (msg.value * fee) / DENOMINATOR;
            valueForSwap = msg.value - feeAmount;
        }

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
        unchecked {
            // Safe: amounts[0] <= valueForSwap (enforced by router)
            uint unusedAmount = valueForSwap - amounts[0];
            if (unusedAmount > 0) {
                payable(msg.sender).sendValue(unusedAmount);
            }
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
        uint feeAmount;

        unchecked {
            // Safe: fee is capped at 5% (500/10000)
            feeAmount = (amountIn * fee) / DENOMINATOR;
            amountIn -= feeAmount;
        }

        feeAmount = _processReferralFee(feeAmount, path[0]);
        if (feeAmount > 0) {
            inputToken.transfer(feeRecipient, feeAmount);
        }

        // Adjust amountOutMin proportionally to account for reduced input
        uint adjustedAmountOutMin;
        unchecked {
            // Safe: amountIn < originalAmountIn
            adjustedAmountOutMin = (amountOutMin * amountIn) / originalAmountIn;
        }

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
        uint feeAmount;
        uint unusedAmount;

        unchecked {
            // Safe: fee is capped at 5% (500/10000)
            feeAmount = (amounts[0] * fee) / DENOMINATOR;
            // Safe: actualTokensReceived >= amounts[0] + feeAmount (enforced by router and fee calculation)
            unusedAmount = actualTokensReceived - amounts[0] - feeAmount;
        }

        // Refund any unused tokens to user before processing referral fee
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
        uint feeAmount;
        uint unusedAmount;

        unchecked {
            // Safe: fee is capped at 5% (500/10000)
            feeAmount = (amounts[0] * fee) / DENOMINATOR;
            // Safe: actualTokensReceived >= amounts[0] + feeAmount (enforced by router and fee calculation)
            unusedAmount = actualTokensReceived - amounts[0] - feeAmount;
        }

        // Refund any unused tokens to user before processing referral fee
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

        for (uint256 i = startIndex; i < endIndex; ) {
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

            unchecked {
                // Safe: i < endIndex <= length, so i + 1 won't overflow
                ++i;
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

        for (uint256 i = 0; i < length; ) {
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

            unchecked {
                // Safe: i < length, so i + 1 won't overflow
                ++i;
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

        for (uint256 i = 0; i < length; ) {
            totalRewards[i] = referralRewardsOf[referrer][tokens[i]]
                .totalReward;
            availableRewards[i] = referralRewardsOf[referrer][tokens[i]]
                .availableReward;

            unchecked {
                // Safe: i < length, so i + 1 won't overflow
                ++i;
            }
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

    /**
     * @dev Checks if setting a referrer would create a cycle in the referral chain
     * @param user The user setting their referrer
     * @param referrer The proposed referrer
     * @return true if a cycle would be created
     */
    function _wouldCreateCycle(
        address user,
        address referrer
    ) internal view returns (bool) {
        address current = referrer;
        uint256 depth;
        uint256 maxDepth = 100; // Prevent infinite loops

        while (current != address(0) && depth < maxDepth) {
            if (current == user) {
                return true; // Cycle detected
            }
            current = referrerOf[current];

            unchecked {
                // Safe: depth < maxDepth (100), so depth + 1 won't overflow
                ++depth;
            }
        }

        return false;
    }

    function setReferrer(address referrer) external {
        if (referrer == address(0)) revert InvalidReferrer(); // cannot set a zero address as referrer
        if (referrer == msg.sender) revert InvalidReferrer(); // cannot set yourself as referrer
        if (referrerOf[msg.sender] != address(0)) revert InvalidReferrer(); // user already has a referrer
        if (_wouldCreateCycle(msg.sender, referrer))
            revert ReferralCycleDetected(); // prevent circular references

        referrerOf[msg.sender] = referrer;

        unchecked {
            // Safe: referralsCountOf increment won't realistically overflow
            ++referralsCountOf[referrer];
        }

        emit ReferrerSet(referrer, msg.sender);
    }

    // Admin functions

    function setReferrerOf(address referrer, address user) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        if (referrer == address(0)) revert InvalidReferrer(); // cannot set a zero address as referrer
        if (referrer == user) revert InvalidReferrer(); // cannot refer yourself
        if (_wouldCreateCycle(user, referrer)) revert ReferralCycleDetected(); // prevent circular references

        referrerOf[user] = referrer;

        unchecked {
            // Safe: referralsCountOf increment won't realistically overflow
            ++referralsCountOf[referrer];
        }

        emit ReferrerSet(referrer, user);
    }

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

    function setReferralFeeLvl2(uint _referralFeeLvl2) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        require(_referralFeeLvl2 <= DENOMINATOR, "Max 100% referral fee");
        referralFeeLvl2 = _referralFeeLvl2;
        emit ReferralFeeLevelSet(2, _referralFeeLvl2);
    }

    function setReferralFeeLvl3(uint _referralFeeLvl3) external {
        if (msg.sender != feeRecipient) revert NotAuthorized();
        require(_referralFeeLvl3 <= DENOMINATOR, "Max 100% referral fee");
        referralFeeLvl3 = _referralFeeLvl3;
        emit ReferralFeeLevelSet(3, _referralFeeLvl3);
    }

    receive() external payable {}
}
