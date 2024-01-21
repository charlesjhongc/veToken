// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { TestVeToken } from "test/Setup.t.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract TestVeTokenBalance is TestVeToken {
    using BalanceSnapshot for Snapshot;

    function testCreateLockTwoUsesSameBlock() public {
        uint256 total = 0;

        uint256 bobStakeAmount = 15 * 365 days;
        uint256 bobTokenId = _stakeAndValidate(bob, bobStakeAmount, 1 weeks);
        uint256 expectedBobInitvBal = 15 * 7 days;
        assertEq(vt.vBalanceOf(bobTokenId), expectedBobInitvBal);
        total = total + expectedBobInitvBal;
        assertEq(vt.totalvBalance(), total);

        uint256 aliceStakeAmount = 31 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 3 weeks);
        uint256 expectedAliceInitvBal = 31 * 3 weeks;
        assertEq(vt.vBalanceOf(aliceTokenId), expectedAliceInitvBal);
        total = total + expectedAliceInitvBal;
        assertEq(vt.totalvBalance(), total);

        // check epoch index
        assertEq(vt.epoch(), 2);
        assertEq(vt.userPointEpoch(bobTokenId), 1);
        assertEq(vt.userPointEpoch(aliceTokenId), 1);
    }

    function testCreateLockTwoUsersDifferentBlock() public {
        uint256 total = 0;

        uint256 bobStakeAmount = 15 * 365 days;
        uint256 bobTokenId = _stakeAndValidate(bob, bobStakeAmount, 1 weeks);
        uint256 expectedBobInitvBal = 15 * 7 days;
        assertEq(vt.vBalanceOf(bobTokenId), expectedBobInitvBal);
        total = total + expectedBobInitvBal;
        assertEq(vt.totalvBalance(), total);

        // fastforward 1 day
        uint256 dt = 1 days;
        vm.warp(block.timestamp + dt);
        vm.roll(block.number + 1);

        total = total - (dt * 15);

        uint256 aliceStakeAmount = 31 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 1 weeks);
        // after rounding, end - start = 6 days
        uint256 expectedAliceInitvBal = 31 * 6 days;
        assertEq(vt.vBalanceOf(aliceTokenId), expectedAliceInitvBal);
        total = total + expectedAliceInitvBal;
        assertEq(vt.totalvBalance(), total);

        // check epoch index
        assertEq(vt.epoch(), 2);
        assertEq(vt.userPointEpoch(bobTokenId), 1);
        assertEq(vt.userPointEpoch(aliceTokenId), 1);
    }

    function testCreateLock_and_Withdraw_DifferentTime() public {
        // alice and bob despoit for different amount and time
        uint256 totalBalance = 0;
        uint256 aliceStakeAmount = 1 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 2 weeks);
        uint256 aliceBalance = _initialvBalance(aliceStakeAmount, 2 weeks);
        totalBalance = totalBalance + aliceBalance;
        assertEq(vt.vBalanceOf(aliceTokenId), aliceBalance);
        assertEq(vt.totalvBalance(), totalBalance);

        uint256 bobStakeAmount = 5 * 365 days;
        uint256 bobTokenId = _stakeAndValidate(bob, bobStakeAmount, 1 weeks);
        uint256 bobBalance = _initialvBalance(bobStakeAmount, 1 weeks);
        totalBalance = totalBalance + bobBalance;
        assertEq(vt.vBalanceOf(bobTokenId), bobBalance);
        assertEq(vt.totalvBalance(), totalBalance);

        // fast forward 1 weeks, bob's lock is expired
        uint256 dt = 1 days;
        vm.warp(block.timestamp + 7 * dt);
        vm.roll(block.number + 1);
        // sub Bob's all balance
        totalBalance = totalBalance - bobBalance;
        // sub Alice's delined balance ()
        totalBalance = totalBalance - (1 * 7 days);

        // alice's balance
        uint256 expectedAliceBalance = 1 weeks;
        assertEq(vt.vBalanceOf(aliceTokenId), expectedAliceBalance, "Alice's balance is not as expected");

        // bob's balance
        // bob's lock has ended so the balance is 0
        uint256 expectedBobBalance = 0;
        assertEq(vt.vBalanceOf(bobTokenId), expectedBobBalance);

        assertEq(vt.totalvBalance(), totalBalance);
    }

    function testCreateLock_and_OneEarlyWithdraw() public {
        // alice and bob despoit for same amount and time
        uint256 totalBalance = 0;
        uint256 aliceStakeAmount = 5 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 2 weeks);
        uint256 aliceBalance = _initialvBalance(aliceStakeAmount, 2 weeks);
        totalBalance = totalBalance + aliceBalance;
        assertEq(vt.vBalanceOf(aliceTokenId), aliceBalance);
        assertEq(vt.totalvBalance(), totalBalance);

        uint256 bobStakeAmount = 5 * 365 days;
        uint256 bobTokenId = _stakeAndValidate(bob, bobStakeAmount, 2 weeks);
        uint256 bobBalance = _initialvBalance(bobStakeAmount, 2 weeks);
        totalBalance = totalBalance + bobBalance;
        assertEq(vt.vBalanceOf(bobTokenId), bobBalance);
        assertEq(vt.totalvBalance(), totalBalance);

        // fast forward 1 week
        vm.warp(block.timestamp + 1 weeks);

        // Alice early withdraw 1 week beforehand,
        // calculate the balacence for alice and bob respectively
        uint256 aliceDeclineBalance = aliceBalance;
        uint256 bobDeclineBalance = 5 * 1 weeks;
        totalBalance = totalBalance - aliceDeclineBalance + bobDeclineBalance;
        vm.prank(alice);
        vt.withdrawEarly(aliceTokenId);
        assertEq(vt.totalvBalance(), totalBalance, "totalBalance not equal");

        // check epoch index
        assertEq(vt.epoch(), 3);
        assertEq(vt.userPointEpoch(bobTokenId), 1);
        assertEq(vt.userPointEpoch(aliceTokenId), 2);
    }

    /*****************************************
     *   Uint Test for balance of single Ve  *
     *****************************************/
    function testVbalanceOf() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 vBalance = vt.vBalanceOf(tokenId);
        uint256 expectBalance = 10 * 2 weeks;
        assertEq(vBalance, expectBalance, "Balance is not equal");

        // fast forward 1 week
        vm.warp(block.timestamp + 1 weeks);
        expectBalance = 10 * 1 weeks;
        vBalance = vt.vBalanceOf(tokenId);
        assertEq(vBalance, expectBalance);
    }

    function testVBalanceOfAtTime() public {
        uint256 aliceStakeAmount = 10 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 2 weeks);

        // fast forward 1 week
        vm.warp(block.timestamp + 1 weeks);
        vm.roll(block.number + 1);

        // calculate Alice's balance
        // declineRate  = locking_amount / MAX_lock_duration = (10 * 365 days)/ 365days = 10
        // exptectedBalance = initial balance - decline balance = 10 * 2 weeks - 10 * 1 weeks = 10 * 1 week
        uint256 expectAliceBalance = 10 * 7 days;
        assertEq(vt.vBalanceOfAtTime(aliceTokenId, block.timestamp), expectAliceBalance);
    }

    function testCannotGetVBalabnceInFuture() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.expectRevert("Invalid timestamp");
        vt.vBalanceOfAtTime(tokenId, block.timestamp + 1 weeks);
    }

    function testVBalanceOfAtBlk() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);

        // next block and 1 week later
        uint256 expectBalance = 10 * 1 weeks;
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1 weeks);
        assertEq(vt.vBalanceOfAtBlk(tokenId, block.number), expectBalance);
    }

    // test testVBalanceOfAtBlk() when target block != current block
    function testVBalanceOfAtBlkPast() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 initialBalacne = _initialvBalance(DEFAULT_STAKE_AMOUNT, 2 weeks);

        // Assume current block.number is 0, then fast forward to 10 blocks and 2 weeks later,
        // but query the 5th block at the beginning of second week (1 weeks later)
        uint256 dBlock = 1;
        uint256 dt = 1 days;
        uint256 targetBlock = (block.number + 5);
        vm.roll(block.number + 10 * dBlock);
        vm.warp(block.timestamp + 14 * dt);

        uint256 expectedBalance = initialBalacne - 10 * 7 * dt;
        assertEq(vt.vBalanceOfAtBlk(tokenId, targetBlock), expectedBalance);
    }

    // test vBalanceOfAtBlk() when the target block is before lastPoint.blk
    function testVBalanceOfAtBlkBeforeLastPoint() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 4 weeks);
        uint256 initialBalance = _initialvBalance(DEFAULT_STAKE_AMOUNT, 4 weeks);

        assertEq(vt.userPointEpoch(tokenId), 1);
        assertEq(vt.vBalanceOfAtBlk(tokenId, block.number), initialBalance);

        // fast forward 2 weeks and user extend lock for 4 weeks, so the the vBalance is 2 weeks more
        // The userEpoch should be 2 (createLock, extendLock)
        // And the lastPoint of user should be updated now becase user extendedLock
        vm.warp(block.timestamp + 2 weeks);
        vm.roll(block.number + 2);
        vm.prank(user);
        vt.extendLock(tokenId, 4 weeks);
        uint256 expectedBalance = (initialBalance - 10 * 2 weeks) + (10 * 2 weeks);
        assertEq(vt.userPointEpoch(tokenId), 2);
        assertEq(vt.vBalanceOfAtBlk(tokenId, block.number), expectedBalance);
        assertEq(vt.epoch(), 3);

        // Query the second week balance (1 week passed since created)
        // expetedBalance  = initialBalance - 1 week passed
        expectedBalance = initialBalance - 10 * 1 weeks;
        assertEq(vt.vBalanceOfAtBlk(tokenId, block.number - 1), expectedBalance);

        // Query the first week balance (createLock) to verify
        assertEq(vt.vBalanceOfAtBlk(tokenId, block.number - 2), initialBalance);
    }

    // test vBalanceOfAtTime() when the target _t is before lastPoint.ts
    function testVBalanceOfAtTimeBeforeLastPoint() public {
        uint256 userEpoch = 0;
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 4 weeks);
        uint256 initialBalance = _initialvBalance(DEFAULT_STAKE_AMOUNT, 4 weeks);

        assertEq(vt.userPointEpoch(tokenId), ++userEpoch);
        assertEq(vt.vBalanceOfAtTime(tokenId, block.timestamp), initialBalance);

        // fast forward 2 weeks and user extend lock for 3 weeks, so the the vBalance is 1 week more
        // The userEpoch should be 2 (createLock, extendLock)
        // And the lastPoint of user should be updated now becase user extendedLock
        vm.warp(block.timestamp + 2 weeks);
        vm.roll(block.number + 1);
        vm.prank(user);
        vt.extendLock(tokenId, 3 weeks);
        assertEq(vt.userPointEpoch(tokenId), ++userEpoch);

        // Query the second week balance (1 week passed since created)
        // expetedBalance  = initialBalance - 1 week passed
        uint256 expectedBalance = (initialBalance - (10 * 1 weeks));
        assertEq(vt.vBalanceOfAtTime(tokenId, block.timestamp - 1 weeks), expectedBalance);

        // Continue fast forward 1 week, so now is the 4th week(3 weeks passed since createLock)
        // User extend lock for 3 weeks, so the lock 1 weeek more (expired in 7th week)
        vm.warp(block.timestamp + 1 weeks);
        vm.roll(block.number + 1);
        vm.prank(user);
        vt.extendLock(tokenId, 3 weeks);
        assertEq(vt.userPointEpoch(tokenId), ++userEpoch);

        // Fast forward 2 week, now is 6th week(5 weeks passed since created)
        // Query the 3rd week balance
        // expetedBalance = (initialBalance - 2 weeks passed) + (1 week extended at that time);
        vm.warp(block.timestamp + 2 weeks);
        vm.roll(block.number + 1);
        expectedBalance = ((initialBalance - 10 * 2 weeks) + (10 * 1 weeks));
        assertEq(vt.vBalanceOfAtTime(tokenId, block.timestamp - 3 weeks), expectedBalance);

        // Query the 1st week balance to verify
        assertEq(vt.vBalanceOfAtTime(tokenId, block.timestamp - 5 weeks), initialBalance);
    }

    function testCannotGetVBalabnceAtFutureBlk() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        vm.expectRevert("Invalid block number");
        // get balance in future block
        vt.vBalanceOfAtBlk(tokenId, block.number + 1);
    }

    /***********************************
     *   Uint Test for Total Balance *
     ***********************************/
    function testTotalvBalance() public {
        _stakeAndValidate(alice, DEFAULT_STAKE_AMOUNT, 2 weeks);
        _stakeAndValidate(bob, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 totalvBalance = vt.totalvBalance();
        uint256 expectvBalance = _initialvBalance(2 * DEFAULT_STAKE_AMOUNT, 2 weeks);
        assertEq(totalvBalance, expectvBalance);
    }

    function testTotalvBalanceAtTime() public {
        _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 totalvBalance = vt.totalvBalanceAtTime(block.timestamp);
        uint256 expectvBalance = 10 * 2 weeks;
        assertEq(totalvBalance, expectvBalance);

        // test 1 week has passed
        vm.warp(block.timestamp + 1 weeks);
        vm.roll(block.number + 1);
        totalvBalance = vt.totalvBalanceAtTime(block.timestamp);
        expectvBalance = 10 * 1 weeks;
        assertEq(totalvBalance, expectvBalance);
    }

    function testCannotGetTotalvBalanceInFuture() public {
        vm.expectRevert("Invalid timestamp");
        vt.totalvBalanceAtTime(block.timestamp + 1 weeks);
    }

    function testTotalvBalanceAtBlk() public {
        _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 totalvBalance = vt.totalvBalanceAtBlk(block.number);
        uint256 expectvBalance = 10 * 2 weeks;
        assertEq(totalvBalance, expectvBalance);

        // 10 blocks and 1 week has passed
        expectvBalance = 10 * 1 weeks;
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 1 weeks);
        assertEq(vt.totalvBalanceAtBlk(block.number), expectvBalance);
    }

    function testCannotGetTotalvBalanceAtFutureBlk() public {
        vm.expectRevert("Invalid block number");
        vt.totalvBalanceAtBlk(block.number + 1);
    }

    // test totalVbalanceAtBlk when target block != current block
    function testTotalVBalanceAtBlkPast() public {
        // alice and bob despoit for same amount and same time
        uint256 totalBalance = 0;
        uint256 aliceStakeAmount = 10 * 365 days;
        uint256 aliceTokenId = _stakeAndValidate(alice, aliceStakeAmount, 2 weeks);
        uint256 aliceBalance = _initialvBalance(aliceStakeAmount, 2 weeks);
        totalBalance = totalBalance + aliceBalance;
        assertEq(vt.vBalanceOf(aliceTokenId), aliceBalance);
        assertEq(vt.totalvBalance(), totalBalance);

        uint256 bobStakeAmount = 10 * 365 days;
        uint256 bobTokenId = _stakeAndValidate(bob, bobStakeAmount, 2 weeks);
        uint256 bobBalance = _initialvBalance(bobStakeAmount, 2 weeks);
        totalBalance = totalBalance + bobBalance;
        assertEq(vt.vBalanceOf(bobTokenId), bobBalance);
        assertEq(vt.totalvBalance(), totalBalance);

        // Assume current block.number is 0, then fast forward to 10 blocks and 2 weeks later,
        // but query the 5th block at the beginning of second week (1 weeks later)
        uint256 dBlock = 1;
        uint256 dt = 1 days;
        uint256 targetBlock = (block.number + 5);
        vm.roll(block.number + 10 * dBlock);
        vm.warp(block.timestamp + 14 * dt);

        // total balance -= (Alice_DeclineRate * 7 days + Bob_DeclineRate * 7 days)
        totalBalance = totalBalance - (2 * 10 * 7 * dt);
        assertEq(vt.totalvBalanceAtBlk(targetBlock), totalBalance);
    }

    // test vBalanceOfAtTime() when the target _t is before lastPoint.ts
    function testTotalVBalanceAtTimeBeforeLastPoint() public {
        _stakeAndValidate(alice, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 aliceBalance = _initialvBalance(DEFAULT_STAKE_AMOUNT, 2 weeks);

        assertEq(vt.epoch(), 1);
        assertEq(vt.totalvBalanceAtTime(block.timestamp), aliceBalance);

        // fast forward 1 week and second user createlock
        vm.warp(block.timestamp + 1 weeks);
        vm.roll(block.number + 1);
        uint256 bobTokenId = _stakeAndValidate(bob, DEFAULT_STAKE_AMOUNT, 3 weeks);
        uint256 bobBalance = _initialvBalance(DEFAULT_STAKE_AMOUNT, 3 weeks);
        assertEq(vt.epoch(), 2);

        // verify the totalBalance of 1st week when Alcie createLock
        assertEq(vt.totalvBalanceAtTime(block.timestamp - 1 weeks), aliceBalance);

        // Continue fast forward 2 week
        // Bob extend lock for 2 weeks, so now Bob's balance is 1 week more(expired in 6th week)
        vm.warp(block.timestamp + 2 weeks);
        vm.roll(block.number + 1);
        vm.prank(bob);
        vt.extendLock(bobTokenId, 2 weeks);
        // epoch times = (alice createLock, bob createLock, 3rd weekPoint, Bob extendLock)
        assertEq(vt.epoch(), 4);

        // Query the totalvBalance of third week when Alice's lock has expired
        // Bob's lock has passed 1 week
        uint256 totalBalance = bobBalance - 10 * 1 weeks;
        assertEq(vt.totalvBalanceAtTime(block.timestamp - 1 weeks), totalBalance);

        // Query the second week when Alice's lock has passed 1 week,
        // And Bob just credted lock
        totalBalance = (aliceBalance - 10 * 1 weeks) + bobBalance;
        assertEq(vt.totalvBalanceAtTime(block.timestamp - 2 weeks), totalBalance);
    }

    // test totalVBalanceAtBlk() when the target block is before lastPoint.blk
    function testTotalVBalanceAtBlkBeforeLastPoint() public {
        _stakeAndValidate(alice, DEFAULT_STAKE_AMOUNT, 4 weeks);
        uint256 aliceBalance = _initialvBalance(DEFAULT_STAKE_AMOUNT, 4 weeks);

        assertEq(vt.epoch(), 1);
        assertEq(vt.totalvBalanceAtBlk(block.number), aliceBalance);

        // fast forward 2 weeks and 2 blocks, second user createlock
        vm.warp(block.timestamp + 2 weeks);
        vm.roll(block.number + 2);
        _stakeAndValidate(bob, DEFAULT_STAKE_AMOUNT, 2 weeks);
        uint256 bobBalance = _initialvBalance(DEFAULT_STAKE_AMOUNT, 2 weeks);

        // verify the totalvBalance now
        // expected balance = alice's balance - 2 weeks passed + bob's initial balance
        uint256 expectedBalance = (aliceBalance - 10 * 2 weeks) + bobBalance;
        assertEq(vt.epoch(), 3);
        assertEq(vt.totalvBalanceAtBlk(block.number), expectedBalance);

        // verify the totalBalance of second  week when Alice's lock has passed 1 week
        expectedBalance = aliceBalance - 10 * 1 weeks;
        assertEq(vt.totalvBalanceAtBlk(block.number - 1), expectedBalance);

        // Verify the totalvBalanceAtBlk when first week Alice createLock
        assertEq(vt.totalvBalanceAtBlk(block.number - 2), aliceBalance);
    }
}
