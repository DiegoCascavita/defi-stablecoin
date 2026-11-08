// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

/**
 * @title Handler
 * @notice Restricts fuzz calls to valid paths for invariant testing.
 */
contract Handler is Test {
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    ERC20Mock public weth;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        weth.mint(msg.sender, amountCollateral);
        weth.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(weth), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address user = _getUser(collateralSeed);
        if (user == address(0)) return;

        uint256 maxCollateral = engine.getCollateralBalanceOfUser(user, address(weth));
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) return;

        vm.startPrank(user);
        // May revert if HF broken — that's fine for fail_on_revert = false
        try engine.redeemCollateral(address(weth), amountCollateral) {} catch {}
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) return;

        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;

        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // NOTE: We intentionally do NOT fuzz oracle price crashes here.
    // A sudden price drop can make the system temporarily undercollateralized until
    // liquidations clear bad debt — that breaks the solvency invariant by design.
    // Liquidation paths are covered in unit tests instead.

    function _getUser(uint256 seed) private view returns (address) {
        if (usersWithCollateralDeposited.length == 0) return address(0);
        return usersWithCollateralDeposited[seed % usersWithCollateralDeposited.length];
    }

    function getUsersLength() external view returns (uint256) {
        return usersWithCollateralDeposited.length;
    }
}
