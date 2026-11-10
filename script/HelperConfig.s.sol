// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

/**
 * @title HelperConfig
 * @notice Network-aware config: Anvil mocks locally; Sepolia uses public Chainlink feed + WETH.
 * @dev Sepolia path returns addresses only — it does not broadcast. Deploy with your own
 *      `PRIVATE_KEY` / RPC when you are ready (`forge script … --broadcast --verify`).
 */
contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address weth;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @notice Chainlink ETH/USD AggregatorV3 on Sepolia (8 decimals).
    address public constant SEPOLIA_WETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    /// @notice Canonical WETH9 on Sepolia (Uniswap).
    address public constant SEPOLIA_WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            // Anvil (31337) and unknown local chains → mocks
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /**
     * @notice Public Sepolia addresses for a future owner-run deploy (no broadcast here).
     * @dev Requires `PRIVATE_KEY` in the environment when constructing on chain id 11155111.
     */
    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: SEPOLIA_WETH_USD_FEED,
            weth: SEPOLIA_WETH,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e18);
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            weth: address(wethMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
