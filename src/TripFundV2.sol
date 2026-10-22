// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {TripFundV1} from "./TripFundV1.sol";

contract TripFundV2 is TripFundV1 {
    using SafeERC20 for IERC20;

    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);

    function contributeFor(address beneficiary, uint256 amount) external {
        require(beneficiary != address(0), "Zero beneficiary address");
        require(amount > 0, "Zero amount");
        require(block.timestamp < deadline, "Deadline passed");

        contributions[beneficiary] += amount;
        totalRaised += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit ContributedFor(msg.sender, beneficiary, amount);
    }
}
