// contracts/NFT.sol
// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ILendingPool {
    struct ReserveConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: Reserve is active
        //bit 57: reserve is frozen
        //bit 58: borrowing is enabled
        //bit 59: stable rate borrowing enabled
        //bit 60-63: reserved
        //bit 64-79: reserve factor
        uint256 data;
    }

    struct ReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        //the current stable borrow rate. Expressed in ray
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external returns (uint256);

    function getReserveData(address asset) external view returns (ReserveData memory);
}

contract AaveWrapper is Ownable {
    using SafeERC20 for IERC20;
    address public lendingPool;

    struct DepositInfo {
        uint256 amount;
    }

    struct BorrowInfo {
        uint256 amount;
    }

    mapping(bytes32 => DepositInfo) depositInfo;
    mapping(bytes32 => BorrowInfo) borrowInfo;

    constructor() {}

    function setLendingPool(address _pool) external onlyOwner {
        require(_pool != address(0), "AaveWrapper: invalid pool");
        lendingPool = _pool;
    }

    function depositAndBorrow(
        address collateralToken,
        uint256 collateralAmount,
        address debtToken,
        uint256 DebtAmount
    ) external {
        bytes32 depositKey = _makeHash(msg.sender, collateralToken);
        depositInfo[depositKey].amount += collateralAmount;
        bytes32 borrowKey = _makeHash(msg.sender, debtToken);
        borrowInfo[borrowKey].amount += DebtAmount;

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);
        if (IERC20(collateralToken).allowance(address(this), lendingPool) < collateralAmount)
            IERC20(collateralToken).safeApprove(lendingPool, ~uint256(0));
        ILendingPool(lendingPool).deposit(collateralToken, collateralAmount, address(this), 0);
        ILendingPool(lendingPool).borrow(debtToken, DebtAmount, 1, 0, address(this));
        IERC20(debtToken).safeTransfer(msg.sender, DebtAmount);
    }

    // collateralToken -> aToken address
    // debtToken

    function paybackAndWithdraw(
        address collateralToken,
        uint256 collateralAmount,
        address debtToken,
        uint256 DebtAmount
    ) external {
        bytes32 depositKey = _makeHash(msg.sender, collateralToken);
        bytes32 borrowKey = _makeHash(msg.sender, debtToken);
        require(depositInfo[depositKey].amount >= collateralAmount, "Wrapper: invalid collateral Amount");
        require(borrowInfo[borrowKey].amount >= DebtAmount, "Wrapper: invalid debt Amount");
        depositInfo[depositKey].amount -= collateralAmount;
        borrowInfo[borrowKey].amount -= DebtAmount;

        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), DebtAmount);
        if (IERC20(debtToken).allowance(address(this), lendingPool) < DebtAmount)
            IERC20(debtToken).safeApprove(lendingPool, ~uint256(0));
        ILendingPool(lendingPool).repay(debtToken, DebtAmount, 1, address(this));

        uint256 amountToWithdraw = ILendingPool(lendingPool).withdraw(collateralToken, collateralAmount, address(this));
        IERC20(collateralToken).safeTransfer(msg.sender, amountToWithdraw);
    }

    function _makeHash(address user, address token) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, token));
    }

    function payback(address debtToken, uint256 DebtAmount) external {
        bytes32 borrowKey = _makeHash(msg.sender, debtToken);
        require(borrowInfo[borrowKey].amount >= DebtAmount, "Wrapper: invalid debt Amount");
        borrowInfo[borrowKey].amount -= DebtAmount;
        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), DebtAmount);
        if (IERC20(debtToken).allowance(address(this), lendingPool) < DebtAmount)
            IERC20(debtToken).safeApprove(lendingPool, ~uint256(0));
        ILendingPool(lendingPool).repay(debtToken, DebtAmount, 1, address(this));
    }

    function Withdraw(address collateralToken, uint256 collateralAmount) external {
        bytes32 depositKey = _makeHash(msg.sender, collateralToken);
        require(depositInfo[depositKey].amount >= collateralAmount, "Wrapper: invalid collateral Amount");
        depositInfo[depositKey].amount -= collateralAmount;
        uint256 amountToWithdraw = ILendingPool(lendingPool).withdraw(collateralToken, collateralAmount, address(this));
        IERC20(collateralToken).safeTransfer(msg.sender, amountToWithdraw);
    }

    function getUserDepositAmount(address collateralToken, address user) external view returns(uint256) {
        return depositInfo[_makeHash(user, collateralToken)].amount;
    }

    function getBorrowAmount(address debtToken, address user) external view returns(uint256) {
        return borrowInfo[_makeHash(user, debtToken)].amount;
    }
}
