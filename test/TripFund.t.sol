// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {TripFund} from "../src/TripFund.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TripFundTest is Test {
    MockToken token;
    TripFund fund;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new MockToken();
        token.mint(alice, 100e18);
        token.mint(bob, 50e18);

        fund = new TripFund(address(token), address(this), 100e18, block.timestamp + 1 days);
    }

    function testContribute() public {
        vm.startPrank(alice);

        token.approve(address(fund), 40e18);
        fund.contribute(40e18);

        vm.stopPrank();

        assertEq(token.balanceOf(alice), 60e18);
        assertEq(token.balanceOf(address(fund)), 40e18);
        assertEq(fund.contributions(alice), 40e18);
        assertEq(fund.totalRaised(), 40e18);
    }

    function testTwoContributorsAndRepeatedContribution() public {
        vm.startPrank(alice);
        token.approve(address(fund), 30e18);
        fund.contribute(10e18);
        fund.contribute(20e18);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(fund), 25e18);
        fund.contribute(25e18);
        vm.stopPrank();

        assertEq(fund.contributions(alice), 30e18);
        assertEq(fund.contributions(bob), 25e18);
        assertEq(fund.totalRaised(), 55e18);
        assertEq(token.balanceOf(address(fund)), 55e18);
        assertEq(token.balanceOf(alice), 70e18);
        assertEq(token.balanceOf(bob), 25e18);
    }

    function testZeroAmountRevertsWithoutChangingState() public {
        vm.startPrank(alice);
        token.approve(address(fund), 10e18);
        fund.contribute(10e18);

        vm.expectRevert();
        fund.contribute(0);
        vm.stopPrank();

        assertEq(fund.contributions(alice), 10e18);
        assertEq(fund.totalRaised(), 10e18);
        assertEq(token.balanceOf(alice), 90e18);
        assertEq(token.balanceOf(address(fund)), 10e18);
    }

    function testInsufficientAllowanceRevertsWithoutChangingState() public {
        vm.startPrank(alice);
        token.approve(address(fund), 10e18);
        fund.contribute(10e18);

        vm.expectRevert();
        fund.contribute(1e18);
        vm.stopPrank();

        assertEq(fund.contributions(alice), 10e18);
        assertEq(fund.totalRaised(), 10e18);
        assertEq(token.balanceOf(alice), 90e18);
        assertEq(token.balanceOf(address(fund)), 10e18);
        assertEq(token.allowance(alice, address(fund)), 0);
    }

    function testInsufficientBalanceRevertsWithoutChangingState() public {
        vm.startPrank(alice);
        token.approve(address(fund), 10e18);
        fund.contribute(10e18);
        token.approve(address(fund), 91e18);

        vm.expectRevert();
        fund.contribute(91e18);
        vm.stopPrank();

        assertEq(fund.contributions(alice), 10e18);
        assertEq(fund.totalRaised(), 10e18);
        assertEq(token.balanceOf(alice), 90e18);
        assertEq(token.balanceOf(address(fund)), 10e18);
        assertEq(token.allowance(alice, address(fund)), 91e18);
    }

    function testContributionDeadlineBoundary() public {
        uint256 deadline_ = fund.deadline();
        vm.warp(deadline_ - 1);

        vm.startPrank(alice);
        token.approve(address(fund), 20e18);
        fund.contribute(10e18);

        vm.warp(deadline_);
        vm.expectRevert();
        fund.contribute(10e18);
        vm.stopPrank();

        assertEq(fund.contributions(alice), 10e18);
        assertEq(fund.totalRaised(), 10e18);
        assertEq(token.balanceOf(alice), 90e18);
        assertEq(token.balanceOf(address(fund)), 10e18);
        assertEq(token.allowance(alice, address(fund)), 10e18);
    }

    function testWithdrawAtExactGoalOnlyAfterDeadline() public {
        vm.startPrank(alice);
        token.approve(address(fund), 100e18);
        fund.contribute(100e18);
        vm.stopPrank();

        vm.expectRevert();
        fund.withdraw();
        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(address(fund)), 100e18);

        vm.warp(fund.deadline());
        fund.withdraw();

        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(address(this)), 100e18);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 100e18);
        assertEq(fund.contributions(alice), 100e18);
    }
}
