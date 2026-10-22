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
    event Contributed(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);
    event Refunded(address indexed contributor, uint256 contributionAmount);

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

    function testConstructorRejectsInvalidArguments() public {
        uint256 futureDeadline = block.timestamp + 1 days;

        vm.expectRevert(bytes("Zero token address"));
        new TripFund(address(0), address(this), 100e18, futureDeadline);

        vm.expectRevert(bytes("Zero organizer address"));
        new TripFund(address(token), address(0), 100e18, futureDeadline);

        vm.expectRevert(bytes("Zero goal"));
        new TripFund(address(token), address(this), 0, futureDeadline);

        vm.expectRevert(bytes("Deadline must be in future"));
        new TripFund(address(token), address(this), 100e18, block.timestamp);

        vm.expectRevert(bytes("Deadline must be in future"));
        new TripFund(address(token), address(this), 100e18, block.timestamp - 1);
    }

    function testContributeEmitsEvent() public {
        vm.startPrank(alice);
        token.approve(address(fund), 10e18);

        vm.expectEmit(true, false, false, true, address(fund));
        emit Contributed(alice, 10e18);
        fund.contribute(10e18);
        vm.stopPrank();
    }

    function testWithdrawAboveGoalEmitsEvent() public {
        vm.startPrank(alice);
        token.approve(address(fund), 100e18);
        fund.contribute(100e18);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(fund), 20e18);
        fund.contribute(20e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.expectEmit(true, false, false, true, address(fund));
        emit Withdrawn(address(this), 120e18);
        fund.withdraw();

        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(address(this)), 120e18);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 120e18);
        assertEq(fund.contributions(alice), 100e18);
        assertEq(fund.contributions(bob), 20e18);
    }

    function testOnlyOrganizerCanWithdraw() public {
        vm.startPrank(alice);
        token.approve(address(fund), 100e18);
        fund.contribute(100e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.prank(bob);
        vm.expectRevert(bytes("You are not organizer"));
        fund.withdraw();

        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(address(fund)), 100e18);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testCannotWithdrawWhenGoalNotReached() public {
        vm.startPrank(alice);
        token.approve(address(fund), 40e18);
        fund.contribute(40e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.expectRevert(bytes("Goal not reached"));
        fund.withdraw();

        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(address(fund)), 40e18);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testCannotWithdrawTwice() public {
        vm.startPrank(alice);
        token.approve(address(fund), 100e18);
        fund.contribute(100e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        fund.withdraw();

        vm.expectRevert(bytes("Already withdrawn"));
        fund.withdraw();

        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(address(this)), 100e18);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function testTwoContributorsCanRefundIndependently() public {
        vm.startPrank(alice);
        token.approve(address(fund), 30e18);
        fund.contribute(10e18);
        fund.contribute(20e18);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(fund), 20e18);
        fund.contribute(20e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.expectEmit(true, false, false, true, address(fund));
        emit Refunded(alice, 30e18);
        vm.prank(alice);
        fund.refund();

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), 20e18);
        assertEq(fund.totalRaised(), 50e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 30e18);
        assertEq(token.balanceOf(address(fund)), 20e18);

        vm.prank(bob);
        fund.refund();

        assertEq(fund.contributions(bob), 0);
        assertEq(fund.totalRaised(), 50e18);
        assertEq(token.balanceOf(bob), 50e18);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function testCannotRefundBeforeDeadline() public {
        vm.startPrank(alice);
        token.approve(address(fund), 10e18);
        fund.contribute(10e18);

        vm.expectRevert(bytes("Deadline not passed yet"));
        fund.refund();
        vm.stopPrank();

        assertEq(fund.contributions(alice), 10e18);
        assertEq(token.balanceOf(alice), 90e18);
        assertEq(token.balanceOf(address(fund)), 10e18);
    }

    function testCannotRefundWhenGoalReached() public {
        vm.startPrank(alice);
        token.approve(address(fund), 100e18);
        fund.contribute(100e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.prank(alice);
        vm.expectRevert(bytes("Goal reached"));
        fund.refund();

        assertEq(fund.contributions(alice), 100e18);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(fund)), 100e18);
    }

    function testCannotRefundWithoutContributionOrTwice() public {
        vm.startPrank(alice);
        token.approve(address(fund), 10e18);
        fund.contribute(10e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.prank(bob);
        vm.expectRevert(bytes("There is no contribution from this user"));
        fund.refund();

        vm.prank(alice);
        fund.refund();
        vm.prank(alice);
        vm.expectRevert(bytes("There is no contribution from this user"));
        fund.refund();

        assertEq(fund.contributions(alice), 0);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function testDirectTokenTransferIsNotCountedOrWithdrawn() public {
        vm.prank(bob);
        token.transfer(address(fund), 5e18);

        vm.startPrank(alice);
        token.approve(address(fund), 100e18);
        fund.contribute(100e18);
        vm.stopPrank();

        assertEq(fund.totalRaised(), 100e18);
        assertEq(fund.contributions(bob), 0);
        assertEq(token.balanceOf(address(fund)), 105e18);

        vm.warp(fund.deadline());
        fund.withdraw();

        assertEq(token.balanceOf(address(this)), 100e18);
        assertEq(token.balanceOf(address(fund)), 5e18);
        assertEq(token.balanceOf(bob), 45e18);
    }

    function testDirectTokenTransferIsNotRefundable() public {
        vm.prank(bob);
        token.transfer(address(fund), 5e18);

        vm.startPrank(alice);
        token.approve(address(fund), 40e18);
        fund.contribute(40e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.prank(bob);
        vm.expectRevert(bytes("There is no contribution from this user"));
        fund.refund();

        vm.prank(alice);
        fund.refund();

        assertEq(fund.totalRaised(), 40e18);
        assertEq(fund.contributions(alice), 0);
        assertEq(token.balanceOf(address(fund)), 5e18);
        assertEq(token.balanceOf(bob), 45e18);
    }
}
