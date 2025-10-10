// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract Presale {
    uint256 public hardCap = 3_333 ether;
    uint256 public minBuy = 0.5 ether;
    uint256 public maxBuy = 50 ether;
    uint256 public totalSaleAmount = 5_000_000 ether;
    uint256 public price = (hardCap * 1e18) / totalSaleAmount;

    IERC20 public saleToken;

    /**
     * @notice The address of the deployer, which will receive the raised ETH.
     */
    address public immutable owner;

    /**
     * @notice The total amount of ETH allocated.
     */
    uint256 public totalContributions;

    /**
     * @notice The start date of the sale in unix timestamp.
     */
    uint256 public start;

    /**
     * @notice The end date of the sale in unix timestamp.
     */
    uint256 public end;

    /**
     * @notice Weather users can claim their tokens.
     */
    bool public isClaimingEnabled;

    /**
     * @notice Weather users can refund their contributions.
     */
    bool public isRefundEnabled;

    /**
     * @notice The amount of eth sent by each address.
     */
    mapping(address => uint256) public contribution;

    /**
     * @notice Weather users have claimed their tokens.
     */
    mapping(address => bool) public hasClaimed;

    /**
     * @notice Emits when tokens are bought.
     * @param contributor The address of the contributor.
     * @param amount The amount of eth contributed.
     */

    event Contribution(address indexed contributor, uint256 amount);

    /**
     * @notice Emits when tokens are claimed.
     * @param claimer The address of the claimer.
     * @param amount The amount of tokens claimed.
     */
    event TokensClaimed(address indexed claimer, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    /**
     * @notice Buys tokens with ETH.
     */
    function contribute() external payable {
        require(block.timestamp >= start, "Sale has not started yet");
        require(block.timestamp <= end, "Sale has ended");
        require(msg.value > 0, "Amount must be greater than 0");

        require(
            msg.value >= minBuy,
            "Amount must be greater than the minimum buy"
        );
        require(
            msg.value <= maxBuy - contribution[msg.sender],
            "Amount must be less than the maximum buy"
        );

        require(
            totalContributions + msg.value <= hardCap,
            "Hard cap has been reached"
        );

        // Update the storage variables
        contribution[msg.sender] += msg.value;
        totalContributions += msg.value;

        emit Contribution(msg.sender, msg.value);
    }

    /**
     * @notice Claim tokens if SOFT_CAP is reached,
     * refund otherwise.
     */
    function claim() external {
        require(
            isClaimingEnabled || isRefundEnabled,
            "Claiming is not enabled"
        );
        address buyer = msg.sender;

        // Check if the buyer has bought tokens
        uint256 buyerContribution = contribution[buyer];
        require(buyerContribution > 0, "No contribution");

        if (isRefundEnabled) {
            // Reset the contribution
            delete contribution[buyer];

            // Refund the buyer
            payable(buyer).transfer(buyerContribution);
        } else {
            require(hasClaimed[buyer] == false, "Tokens already claimed");
            hasClaimed[buyer] = true;

            uint256 tokensBought = buyerContribution * price;

            // Send the tokens
            saleToken.transfer(buyer, tokensBought);
            emit TokensClaimed(buyer, tokensBought);
        }
    }

    ///
    /// ADMIN FUNCTIONS

    function setParams(
        uint256 _hardCap,
        uint256 _minBuy,
        uint256 _maxBuy,
        uint256 _totalSaleAmount,
        uint256 _start,
        uint256 _end
    ) external onlyOwner {
        require(_hardCap > 0, "Hard cap must be greater than 0");
        require(_minBuy > 0, "Min buy must be greater than 0");
        require(_maxBuy > _minBuy, "Max buy must be greater than min buy");
        require(
            _totalSaleAmount > 0,
            "Total sale amount must be greater than 0"
        );
        require(_end > _start, "End date must be after start date");

        hardCap = _hardCap;
        minBuy = _minBuy;
        maxBuy = _maxBuy;
        totalSaleAmount = _totalSaleAmount;
        start = _start;
        end = _end;

        price = totalSaleAmount / hardCap;
    }

    function setTokenAddress(address newfTokenAddress) external onlyOwner {
        require(
            newfTokenAddress != address(0),
            "New token address is the zero address"
        );
        saleToken = IERC20(newfTokenAddress);
    }

    function setPrice(uint256 _price) external onlyOwner {
        require(_price > 0, "Price must be greater than 0");
        price = _price;
    }

    function setClaimingEnabled(bool _isClaimingEnabled) external onlyOwner {
        isClaimingEnabled = _isClaimingEnabled;
    }

    function setRefundEnabled(bool _isRefundEnabled) external onlyOwner {
        isRefundEnabled = _isRefundEnabled;
    }

    function withdraw(uint256 _amount) external onlyOwner {
        uint256 amount = _amount == 0 ? address(this).balance : _amount;
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Transfer failed");
    }

    // Useful to rescue stuck tokens
    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(owner, _amount);
    }

    receive() external payable {}
}
