// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployDSC
 * @notice Deploys DSC + DSCEngine for Anvil using HelperConfig mocks.
 *
 * Usage:
 *   anvil
 *   forge script script/DeployDSC.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
 */
contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address weth, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];

        // msg.sender inside a broadcasted script is the Script/Test contract, not the
        // broadcaster — use the key's address explicitly as DSC initial owner.
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(deployer);
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (dsc, engine, helperConfig);
    }
}
