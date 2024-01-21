// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { TestVeToken } from "test/Setup.t.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract TestVeTokenWithdraw is TestVeToken {
    using BalanceSnapshot for Snapshot;

    event Withdraw(address indexed provider, bool indexed lockExpired, uint256 tokenId, uint256 withdrawValue, uint256 burnValue, uint256 ts);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Supply(uint256 prevSupply, uint256 supply);

    function testWithdraw() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 1 weeks);
        uint256 prevSupply = DEFAULT_STAKE_AMOUNT;

        stakerToken = BalanceSnapshot.take(user, address(token));
        lockedToken = BalanceSnapshot.take(address(vt), address(token));

        // pretend 1 week has passed and the lock expired
        vm.startPrank(user);
        vm.warp(block.timestamp + 1 weeks);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, true, tokenId, DEFAULT_STAKE_AMOUNT, 0, block.timestamp);

        // check supply event
        uint256 supply = prevSupply - DEFAULT_STAKE_AMOUNT;
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);

        vt.withdraw(tokenId);
        stakerToken.assertChange(int256(DEFAULT_STAKE_AMOUNT));
        lockedToken.assertChange(-int256(DEFAULT_STAKE_AMOUNT));
        vm.stopPrank();

        // check whether token has burned after withdraw
        vm.expectRevert("ERC721: owner query for nonexistent token");
        vt.ownerOf(tokenId);

        // check epoch index
        // global has 2 points : creat lock, week point
        // user has 2 points : creat lock, withdraw
        assertEq(vt.epoch(), 2);
        assertEq(vt.userPointEpoch(tokenId), 2);
    }

    function testWithdrawEarly() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 prevSupply = DEFAULT_STAKE_AMOUNT;

        stakerToken = BalanceSnapshot.take(user, address(token));
        lockedToken = BalanceSnapshot.take(address(vt), address(token));

        // set earlyWithdrawPenaltyRate from vt
        uint256 earlyWithdrawPenaltyRate = vt.earlyWithdrawPenaltyRate();

        // pretend 1 week has passed and the lock not expired
        vm.warp(block.timestamp + 1 weeks);

        // calculate the panalty
        uint256 expectedPanalty = (DEFAULT_STAKE_AMOUNT * vt.earlyWithdrawPenaltyRate()) / vt.PENALTY_RATE_PRECISION();
        uint256 expectedAmount = DEFAULT_STAKE_AMOUNT - expectedPanalty;
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, false, tokenId, expectedAmount, expectedPanalty, block.timestamp);

        // check supply event
        uint256 supply = prevSupply - expectedAmount - expectedPanalty;
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);

        vm.prank(user);
        vt.withdrawEarly(tokenId);
        uint256 balanceChange = (DEFAULT_STAKE_AMOUNT * earlyWithdrawPenaltyRate) / PENALTY_RATE_PRECISION;
        stakerToken.assertChange(int256(DEFAULT_STAKE_AMOUNT - balanceChange));
        lockedToken.assertChange(-int256(expectedAmount + expectedPanalty));

        // check whether token has burned after withdraw
        vm.expectRevert("ERC721: owner query for nonexistent token");
        vt.ownerOf(tokenId);

        // check epoch index
        // global has 2 points : creat lock, week point
        // user has 2 points : creat lock, withdraw
        assertEq(vt.epoch(), 2);
        assertEq(vt.userPointEpoch(tokenId), 2);
    }

    function testWithdrawByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 prevSupply = DEFAULT_STAKE_AMOUNT;

        stakerToken = BalanceSnapshot.take(user, address(token));
        lockedToken = BalanceSnapshot.take(address(vt), address(token));

        vm.prank(user);
        // check Approval event
        vm.expectEmit(true, true, true, true);
        emit Approval(user, other, tokenId);
        vt.approve(address(other), tokenId);
        vm.prank(other);

        // check Withdraw event
        vm.warp(block.timestamp + 2 weeks);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(other, true, tokenId, DEFAULT_STAKE_AMOUNT, 0, block.timestamp);

        // check supply event
        uint256 supply = prevSupply - DEFAULT_STAKE_AMOUNT;
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);

        vt.withdraw(tokenId);

        stakerToken.assertChange(int256(DEFAULT_STAKE_AMOUNT));
        lockedToken.assertChange(-int256(DEFAULT_STAKE_AMOUNT));

        // check epoch index
        // global has 3 points : creat lock, week point*2
        // user has 2 points : creat lock, withdraw
        assertEq(vt.epoch(), 3);
        assertEq(vt.userPointEpoch(tokenId), 2);
    }
}
