// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether; // $100 DSC at $2000/ETH with 10 ETH

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, weth,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_USER_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(ethUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = 30_000e18
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $100 / $2000 = 0.05 ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    /*//////////////////////////////////////////////////////////////
                         DEPOSIT COLLATERAL
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", USER, 100e18);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(randomToken), 10e18);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           MINT / BURN DSC
    //////////////////////////////////////////////////////////////*/
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanMintDscWithCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        // 10 ETH * $2000 = $20_000 collateral
        // liquidation threshold 50% => max mint $10_000
        uint256 amountToMint = 15_000 ether;
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();
        amountToMint = (amountToMint * 50) / 100 + 1; // just over threshold

        vm.startPrank(USER);
        vm.expectRevert();
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
        assertEq(dsc.balanceOf(USER), 0);
    }

    /*//////////////////////////////////////////////////////////////
                         REDEEM COLLATERAL
    //////////////////////////////////////////////////////////////*/
    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_USER_BALANCE);
    }

    function testCanRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        assertEq(dsc.balanceOf(USER), 0);
        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_USER_BALANCE);
    }

    function testRedeemRevertsIfBreaksHealthFactor() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert();
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             LIQUIDATION
    //////////////////////////////////////////////////////////////*/
    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testLiquidationImprovesHealthFactor() public depositedCollateralAndMintedDsc {
        // Crash ETH price so USER becomes undercollateralized
        // USER: 10 ETH collateral, 100 DSC debt
        // At $2000: collateral $20k, HF = (20k*0.5)/100 = 100
        // At $18:  collateral $180,  HF = (180*0.5)/100 = 0.9 < 1
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = engine.getHealthFactor(USER);
        assertLt(userHealthFactor, 1e18);

        // Liquidator setup: deposit & mint enough DSC to cover debt
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        // With ETH at $18, need more collateral relative to mint — mint only small amount then get DSC another way
        // Simpler: mint DSC to liquidator via dealing / engine with enough collateral at current price
        // At $18/ETH, 10 ETH = $180, max mint = $90. Debt to cover is 100 — not enough!
        // Give liquidator more WETH
        vm.stopPrank();
        ERC20Mock(weth).mint(LIQUIDATOR, 1000 ether);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), 1000 ether);
        engine.depositCollateralAndMintDsc(weth, 1000 ether, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);

        uint256 liquidatorWethBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT);
        uint256 liquidatorWethAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        // Liquidator should receive collateral + 10% bonus
        assertGt(liquidatorWethAfter, liquidatorWethBefore);
        assertEq(engine.getHealthFactor(USER), type(uint256).max); // debt cleared
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           HEALTH FACTOR
    //////////////////////////////////////////////////////////////*/
    function testHealthFactorIsMaxWhenNoDebt() public depositedCollateral {
        assertEq(engine.getHealthFactor(USER), type(uint256).max);
    }

    function testGetters() public view {
        assertEq(engine.getPrecision(), 1e18);
        assertEq(engine.getLiquidationThreshold(), 50);
        assertEq(engine.getLiquidationBonus(), 10);
        assertEq(engine.getMinHealthFactor(), 1e18);
        assertEq(engine.getDsc(), address(dsc));
        assertEq(engine.getCollateralTokenPriceFeed(weth), ethUsdPriceFeed);
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], weth);
    }

    function testCalculateHealthFactor() public view {
        uint256 hf = engine.calculateHealthFactor(100e18, 200e18);
        // (200 * 50 / 100) * 1e18 / 100 = 1e18
        assertEq(hf, 1e18);
    }
}
