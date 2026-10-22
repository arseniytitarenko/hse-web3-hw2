// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TripFundV1} from "../src/TripFundV1.sol";
import {TripFundV2} from "../src/TripFundV2.sol";

contract ProxyTestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TripFundProxyTest is Test {
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);

    ProxyTestToken token;
    TripFundV1 implementation;
    TransparentUpgradeableProxy proxy;
    TripFundV1 fund;

    address adminOwner = address(0xAD01);
    address organizer = address(0x0A6);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new ProxyTestToken();
        token.mint(alice, 100e18);

        implementation = new TripFundV1();
        bytes memory initData =
            abi.encodeCall(TripFundV1.initialize, (address(token), organizer, 100e18, block.timestamp + 1 days));
        proxy = new TransparentUpgradeableProxy(address(implementation), adminOwner, initData);
        fund = TripFundV1(address(proxy));
    }

    function testProxyInitializesStorageAndCreatesOwnedProxyAdmin() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), 100e18);
        assertEq(fund.deadline(), block.timestamp + 1 days);
        assertEq(fund.totalRaised(), 0);
        assertFalse(fund.withdrawn());

        address proxyAdmin = address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
        assertEq(ProxyAdmin(proxyAdmin).owner(), adminOwner);
        assertEq(address(implementation.token()), address(0));
    }

    function testProxyAndImplementationCannotBeInitializedAgain() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        fund.initialize(address(token), organizer, 1, block.timestamp + 2 days);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(token), organizer, 1, block.timestamp + 2 days);
    }

    function testProxyDeploymentRejectsInvalidInitialization() public {
        bytes memory initData =
            abi.encodeCall(TripFundV1.initialize, (address(0), organizer, 100e18, block.timestamp + 1 days));

        vm.expectRevert(bytes("Zero token address"));
        new TransparentUpgradeableProxy(address(implementation), adminOwner, initData);
    }

    function testContributionUsesProxyAddressForApprovalAndBalance() public {
        vm.startPrank(alice);
        token.approve(address(implementation), 10e18);

        vm.expectRevert();
        fund.contribute(10e18);
        assertEq(fund.totalRaised(), 0);

        token.approve(address(proxy), 10e18);
        fund.contribute(10e18);
        vm.stopPrank();

        assertEq(fund.contributions(alice), 10e18);
        assertEq(fund.totalRaised(), 10e18);
        assertEq(token.balanceOf(address(proxy)), 10e18);
        assertEq(token.balanceOf(address(implementation)), 0);
        assertEq(token.balanceOf(alice), 90e18);
    }

    function testOrganizerWithdrawsThroughProxy() public {
        vm.startPrank(alice);
        token.approve(address(proxy), 100e18);
        fund.contribute(100e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.prank(organizer);
        fund.withdraw();

        assertTrue(fund.withdrawn());
        assertEq(fund.totalRaised(), 100e18);
        assertEq(token.balanceOf(organizer), 100e18);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testContributorRefundsThroughProxy() public {
        vm.startPrank(alice);
        token.approve(address(proxy), 40e18);
        fund.contribute(40e18);
        vm.stopPrank();

        vm.warp(fund.deadline());
        vm.prank(alice);
        fund.refund();

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.totalRaised(), 40e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testOnlyProxyAdminOwnerCanUpgrade() public {
        TripFundV2 v2Implementation = new TripFundV2();
        ProxyAdmin admin = _proxyAdmin();

        vm.prank(organizer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, organizer));
        admin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(v2Implementation), bytes(""));
        assertEq(_implementationAddress(), address(implementation));

        vm.prank(adminOwner);
        admin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(v2Implementation), bytes(""));
        assertEq(_implementationAddress(), address(v2Implementation));
    }

    function testUpgradePreservesStateAndAllowsGiftRefund() public {
        uint256 deadline_ = fund.deadline();

        vm.startPrank(alice);
        token.approve(address(proxy), 60e18);
        fund.contribute(20e18);
        vm.stopPrank();

        address proxyAddress = address(proxy);
        TripFundV2 v2Implementation = new TripFundV2();
        vm.warp(deadline_ - 1);
        vm.prank(adminOwner);
        _proxyAdmin().upgradeAndCall(ITransparentUpgradeableProxy(proxyAddress), address(v2Implementation), bytes(""));

        TripFundV2 upgraded = TripFundV2(proxyAddress);
        assertEq(address(upgraded), proxyAddress);
        assertEq(_implementationAddress(), address(v2Implementation));
        assertEq(address(upgraded.token()), address(token));
        assertEq(upgraded.organizer(), organizer);
        assertEq(upgraded.goal(), 100e18);
        assertEq(upgraded.deadline(), deadline_);
        assertEq(upgraded.contributions(alice), 20e18);
        assertEq(upgraded.totalRaised(), 20e18);
        assertEq(token.balanceOf(proxyAddress), 20e18);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        upgraded.initialize(address(token), organizer, 1, deadline_ + 1 days);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        v2Implementation.initialize(address(token), organizer, 1, deadline_ + 1 days);

        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true, proxyAddress);
        emit ContributedFor(alice, bob, 30e18);
        upgraded.contributeFor(bob, 30e18);
        upgraded.contribute(10e18);
        vm.stopPrank();

        assertEq(upgraded.contributions(alice), 30e18);
        assertEq(upgraded.contributions(bob), 30e18);
        assertEq(upgraded.totalRaised(), 60e18);
        assertEq(token.balanceOf(alice), 40e18);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(proxyAddress), 60e18);

        vm.warp(deadline_);
        vm.prank(bob);
        upgraded.refund();
        assertEq(upgraded.contributions(bob), 0);
        assertEq(upgraded.contributions(alice), 30e18);
        assertEq(token.balanceOf(bob), 30e18);
        assertEq(token.balanceOf(proxyAddress), 30e18);

        vm.prank(alice);
        upgraded.refund();
        assertEq(upgraded.contributions(alice), 0);
        assertEq(upgraded.totalRaised(), 60e18);
        assertEq(token.balanceOf(alice), 70e18);
        assertEq(token.balanceOf(proxyAddress), 0);
    }

    function testContributeForChecksInputsAndDeadline() public {
        TripFundV2 v2Implementation = new TripFundV2();
        vm.prank(adminOwner);
        _proxyAdmin().upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(v2Implementation), bytes(""));
        TripFundV2 upgraded = TripFundV2(address(proxy));

        vm.startPrank(alice);
        token.approve(address(proxy), 10e18);

        vm.expectRevert(bytes("Zero beneficiary address"));
        upgraded.contributeFor(address(0), 1e18);

        vm.expectRevert(bytes("Zero amount"));
        upgraded.contributeFor(bob, 0);

        vm.expectRevert();
        upgraded.contributeFor(bob, 11e18);
        assertEq(upgraded.totalRaised(), 0);
        assertEq(token.allowance(alice, address(proxy)), 10e18);

        vm.warp(upgraded.deadline() - 1);
        upgraded.contributeFor(bob, 5e18);
        upgraded.contributeFor(bob, 5e18);

        vm.warp(upgraded.deadline());
        vm.expectRevert(bytes("Deadline passed"));
        upgraded.contributeFor(bob, 1e18);
        vm.stopPrank();

        assertEq(upgraded.contributions(bob), 10e18);
        assertEq(upgraded.totalRaised(), 10e18);
        assertEq(token.balanceOf(alice), 90e18);
        assertEq(token.balanceOf(address(proxy)), 10e18);
    }

    function _proxyAdmin() internal view returns (ProxyAdmin) {
        return ProxyAdmin(address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT)))));
    }

    function _implementationAddress() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(proxy), IMPLEMENTATION_SLOT))));
    }
}
