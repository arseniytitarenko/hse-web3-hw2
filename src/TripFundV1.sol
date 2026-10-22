// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

contract TripFundV1 is Initializable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public organizer;
    uint256 public goal;
    uint256 public deadline;

    mapping(address => uint256) public contributions;
    uint256 public totalRaised;
    bool public withdrawn;

    event Contributed(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);
    event Refunded(address indexed contributor, uint256 contributionAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address token_, address organizer_, uint256 goal_, uint256 deadline_) external initializer {
        require(token_ != address(0), "Zero token address");
        require(organizer_ != address(0), "Zero organizer address");
        require(goal_ > 0, "Zero goal");
        require(deadline_ > block.timestamp, "Deadline must be in future");

        token = IERC20(token_);
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    function contribute(uint256 amount) external {
        require(amount > 0, "Zero amount");
        require(block.timestamp < deadline, "Deadline passed");

        contributions[msg.sender] += amount;
        totalRaised += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Contributed(msg.sender, amount);
    }

    function withdraw() external {
        require(msg.sender == organizer, "You are not organizer");
        require(block.timestamp >= deadline, "Deadline not passed yet");
        require(totalRaised >= goal, "Goal not reached");
        require(!withdrawn, "Already withdrawn");

        withdrawn = true;
        token.safeTransfer(organizer, totalRaised);

        emit Withdrawn(msg.sender, totalRaised);
    }

    function refund() external {
        require(block.timestamp >= deadline, "Deadline not passed yet");
        require(totalRaised < goal, "Goal reached");
        uint256 amount = contributions[msg.sender];
        require(amount > 0, "There is no contribution from this user");

        contributions[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);

        emit Refunded(msg.sender, amount);
    }
}
