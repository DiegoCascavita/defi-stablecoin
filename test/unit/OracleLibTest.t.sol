// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator aggregator;

    function setUp() public {
        aggregator = new MockV3Aggregator(8, 2000e8);
    }

    function testGetTimeout() public view {
        assertEq(OracleLib.getTimeout(AggregatorV3Interface(address(aggregator))), 3 hours);
    }

    function testStalePriceReverts() public {
        vm.warp(block.timestamp + 4 hours);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(aggregator)));
    }

    function testFreshPriceOk() public view {
        (, int256 answer,,,) = OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(aggregator)));
        assertEq(answer, 2000e8);
    }
}
