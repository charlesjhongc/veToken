// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { veToken } from "src/veToken.sol";
import { BalanceSnapshot, Snapshot } from "test/utils/BalanceSnapshot.sol";

contract TestVeToken is Test {
    using BalanceSnapshot for Snapshot;

    address user = vm.addr(uint256(1));
    address bob = vm.addr(uint256(2));
    address alice = vm.addr(uint256(3));
    address other = vm.addr(uint256(4));

    IERC20 token = new ERC20("token", "token");
    veToken vt;

    // set default stake amount to 10 years in order to have integer initial vBalance easily
    uint256 constant DEFAULT_STAKE_AMOUNT = 10 * (365 days);
    uint256 constant DEFAULT_LOCK_TIME = 2 weeks;
    uint256 public constant PENALTY_RATE_PRECISION = 10000;

    // record the balnce of token and veToken
    Snapshot public stakerToken;
    Snapshot public lockedToken;

    function setUp() public {
        // Setup
        vt = new veToken(address(this), address(token));

        // deal eth and token to user, approve token to veToken
        deal(user, 100 ether);
        deal(address(token), user, 100 * 1e18);
        vm.prank(user);
        token.approve(address(vt), type(uint256).max);

        // deal eth and token to user, approve token to veToken
        deal(bob, 100 ether);
        deal(address(token), bob, 100 * 1e18);
        vm.prank(bob);
        token.approve(address(vt), type(uint256).max);

        // deal eth and token to user, approve token to veToken
        deal(alice, 100 ether);
        deal(address(token), alice, 100 * 1e18);
        vm.prank(alice);
        token.approve(address(vt), type(uint256).max);

        // deal eth and token to user, approve token to veToken
        deal(other, 100 ether);
        deal(address(token), other, 100 * 1e18);
        vm.prank(other);
        token.approve(address(vt), type(uint256).max);

        uint256 ts = (block.timestamp / 1 weeks) * 1 weeks;
        vm.warp(ts);

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(other, "Other");
        vm.label(address(this), "TestingContract");
        vm.label(address(token), "TokenContract");
        vm.label(address(vt), "veTokenContract");
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupveToken() public {
        assertEq(vt.owner(), address(this));
        assertEq(address(vt.token()), address(token));
        assertEq(vt.tokenSupply(), 0);
        assertEq(vt.maxLockDuration(), 365 days);
        assertEq(vt.earlyWithdrawPenaltyRate(), 3000);
    }

    /*********************************
     *         Stake utils           *
     *********************************/
    // compute the initial voting power added when staking
    function _initialvBalance(uint256 stakeAmount, uint256 lockDuration) internal view returns (uint256) {
        // Unlocktime is rounded down to weeks
        uint256 unlockTime = ((block.timestamp + lockDuration) * 1 weeks) / 1 weeks;

        // Calculate declining rate first in order to get exactly vBalance as veToken has
        uint256 dRate = stakeAmount / vt.maxLockDuration();
        uint256 vBalance = dRate * (unlockTime - block.timestamp);
        return vBalance;
    }

    function _stakeAndValidate(address staker, uint256 stakeAmount, uint256 lockDuration) internal returns (uint256) {
        vm.startPrank(staker);
        if (token.allowance(staker, address(vt)) == 0) {
            token.approve(address(vt), type(uint256).max);
        }
        uint256 tokenId = vt.createLock(stakeAmount, lockDuration);
        vm.stopPrank();
        return tokenId;
    }
}
