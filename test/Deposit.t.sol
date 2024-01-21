// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { TestVeToken } from "test/Setup.t.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract TestVeTokenDeposit is TestVeToken {
    using BalanceSnapshot for Snapshot;

    enum DepositType {
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE
    }
    event Deposit(address indexed provider, uint256 tokenId, uint256 value, uint256 indexed locktime, DepositType depositType, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    function testFuzzCreateLock(uint256 _amount) public {
        vm.prank(user);
        vm.assume(_amount <= 100 * 1e18);
        vm.assume(_amount > 0);
        vt.createLock(_amount, DEFAULT_LOCK_TIME);
    }

    function testCannotCreateLockWithZero() public {
        vm.prank(user);
        vm.expectRevert("Zero lock amount");
        vt.createLock(0, DEFAULT_LOCK_TIME);
    }

    function testCreateLock() public {
        uint256 prevSupply = 0;
        stakerToken = BalanceSnapshot.take(user, address(token));
        lockedToken = BalanceSnapshot.take(address(vt), address(token));
        uint256 expectedUnlockTime = block.timestamp + DEFAULT_LOCK_TIME;

        uint256 supply = DEFAULT_STAKE_AMOUNT;
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);
        vm.expectEmit(true, true, true, true);
        // emit Deposit(user, nftSupplyBefore + 1, DEFAULT_STAKE_AMOUNT, expectedUnlockTime, DepositType.CREATE_LOCK_TYPE, block.timestamp);

        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);

        stakerToken.assertChange(-int256(DEFAULT_STAKE_AMOUNT));
        lockedToken.assertChange(int256(DEFAULT_STAKE_AMOUNT));

        // check epoch index
        assertEq(vt.epoch(), 1);
        assertEq(vt.userPointEpoch(tokenId), 1);

        uint256 vBalance = vt.vBalanceOf(tokenId);
        // decliningRate = 10, lock duration = 2 weeks (exactly)
        assertEq(vBalance, 10 * 2 weeks);
        // only one user deposit in pool so represent the whole pool
        assertEq(vBalance, vt.totalvBalance());
        // validate unlcok time
        assertEq(vt.unlockTime(tokenId), expectedUnlockTime);
    }

    function testDepositFor() public {
        uint256 prevSupply = DEFAULT_STAKE_AMOUNT;
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        require(tokenId != 0, "No lock created yet");
        uint256 lockEnd = vt.unlockTime(tokenId);

        // check epoch index
        assertEq(vt.epoch(), 1);
        assertEq(vt.userPointEpoch(tokenId), 1);

        stakerToken = BalanceSnapshot.take(user, address(token));
        lockedToken = BalanceSnapshot.take(address(vt), address(token));

        // deposit more on exsisting lock
        uint256 deposit2nd = 5 * 365 days;
        uint256 supply = prevSupply + deposit2nd;
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit Supply(prevSupply, supply);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, tokenId, deposit2nd, lockEnd, DepositType.INCREASE_LOCK_AMOUNT, block.timestamp);
        vt.depositFor(tokenId, deposit2nd);

        stakerToken.assertChange(-(int256(deposit2nd)));
        lockedToken.assertChange(int256(deposit2nd));
        assertEq(vt.vBalanceOf(tokenId), (10 + 5) * 2 weeks);
        assertEq(vt.unlockTime(tokenId), lockEnd);

        // check epoch index
        assertEq(vt.epoch(), 2);
        assertEq(vt.userPointEpoch(tokenId), 2);
    }

    function testDepositForByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(other);
        vt.depositFor(tokenId, 100);
    }

    function testFuzzDepositFor(uint256 _amount) public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(user);
        vm.assume(_amount <= 50 * 1e18);
        vm.assume(_amount > 0);
        vt.depositFor(tokenId, _amount);
    }

    function testExtendLock() public {
        uint256 lockDuration = 2 weeks;
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, lockDuration);
        uint256 lockEndBefore = vt.unlockTime(tokenId);

        uint256 newLockDuration = lockDuration + 8 days;
        uint256 expectedNewEnd = lockEndBefore + 1 weeks; // round to weeks

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, tokenId, 0, expectedNewEnd, DepositType.INCREASE_UNLOCK_TIME, block.timestamp);
        vt.extendLock(tokenId, newLockDuration);

        assertEq(vt.vBalanceOf(tokenId), 10 * (2 weeks + 1 weeks));
        assertEq(vt.unlockTime(tokenId), expectedNewEnd);
        assertEq(vt.epoch(), 2);
        assertEq(vt.userPointEpoch(tokenId), 2);
    }

    function testCannotExtendLockNotAllowance() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 1 weeks);

        vm.prank(other);
        vm.expectRevert("Not approved or owner");
        vt.extendLock(tokenId, 1 weeks);
    }

    function testCannoExtendLockExpired() public {
        uint256 lockTime = 1 weeks;
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, lockTime);

        // pretend 1 week has passed and the lock expired
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(user);
        vm.expectRevert("Lock expired");
        vt.extendLock(tokenId, lockTime);
    }

    function testMerge() public {
        uint256 _stakeAmountFrom = 2 * 356 days;
        uint256 _stakeDurationFrom = 15 weeks;
        uint256 _fromTokenId = _stakeAndValidate(user, _stakeAmountFrom, 15 weeks);
        uint256 _fromUnlockTime = vt.unlockTime(_fromTokenId);

        uint256 _toTokenId = _stakeAndValidate(other, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(other);
        vt.approve(address(user), _toTokenId);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, _toTokenId, _stakeAmountFrom, _fromUnlockTime, DepositType.MERGE_TYPE, block.timestamp);
        vt.merge(_fromTokenId, _toTokenId);

        // check wether the _toToken balance was increased as expected
        // _fromToken lock is longer(15 weeks) then _toToken(2 weeks), so the merged token's lock end would be 15 weeks
        uint256 expectedToBalance = _initialvBalance(_stakeAmountFrom + DEFAULT_STAKE_AMOUNT, _stakeDurationFrom);
        assertEq(expectedToBalance, vt.vBalanceOf(_toTokenId));
        assertEq(expectedToBalance, vt.totalvBalance());

        // check whether fromToken has burned
        vm.expectRevert("ERC721: owner query for nonexistent token");
        vt.ownerOf(_fromTokenId);

        // create 2 locks and merge will generate 2 points
        assertEq(vt.epoch(), 4);
    }
}
