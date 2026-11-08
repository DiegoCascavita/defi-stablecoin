// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title OpenInvariantsTest
 * @notice Stateless fuzz examples on pure/view helpers (complement to Handler invariants).
 */
contract OpenInvariantsTest is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    address weth;
    address ethUsdPriceFeed;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        HelperConfig config;
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, weth,) = config.activeNetworkConfig();
    }

    function testFuzz_getUsdValueNeverRevertsOnReasonableAmounts(uint96 amount) public view {
        uint256 usd = engine.getUsdValue(weth, uint256(amount));
        // price is $2000, so usd = amount * 2000 (in wei precision)
        assertEq(usd, uint256(amount) * 2000);
    }

    function testFuzz_healthFactorZeroDebtIsMax(uint256 collateralUsd) public view {
        uint256 hf = engine.calculateHealthFactor(0, collateralUsd);
        assertEq(hf, type(uint256).max);
    }

    function testFuzz_healthFactorMonotonicInCollateral(uint256 debt, uint256 collA, uint256 collB) public view {
        debt = bound(debt, 1, type(uint128).max);
        collA = bound(collA, 0, type(uint128).max);
        collB = bound(collB, collA, type(uint128).max);
        uint256 hfA = engine.calculateHealthFactor(debt, collA);
        uint256 hfB = engine.calculateHealthFactor(debt, collB);
        assertGe(hfB, hfA);
    }

    function testFuzz_depositAndMintRoundTrip(uint96 collateralAmount) public {
        collateralAmount = uint96(bound(collateralAmount, 1 ether, 100 ether));
        address user = makeAddr("fuzzUser");

        // Fund & approve
        deal(weth, user, collateralAmount);
        vm.startPrank(user);
        IERC20(weth).approve(address(engine), collateralAmount);
        engine.depositCollateral(weth, collateralAmount);

        uint256 collateralUsd = engine.getAccountCollateralValue(user);
        uint256 maxMint = collateralUsd / 2; // 200% CR with 50% threshold
        if (maxMint > 0) {
            engine.mintDsc(maxMint);
            assertEq(dsc.balanceOf(user), maxMint);
            assertGe(engine.getHealthFactor(user), 1e18);

            dsc.approve(address(engine), maxMint);
            engine.burnDsc(maxMint);
            engine.redeemCollateral(weth, collateralAmount);
            assertEq(IERC20(weth).balanceOf(user), collateralAmount);
        }
        vm.stopPrank();
    }
}
