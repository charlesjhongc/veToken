// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { TestVeToken } from "test/Setup.t.sol";

contract TestVeTokenTransfer is TestVeToken {
    function testTransferByOwner() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.startPrank(user);
        vt.approve(other, tokenId);
        vt.transferFrom(user, other, tokenId);
        vm.stopPrank();
        assertEq(vt.ownerOf(tokenId), other);
    }

    function testTransferByOther() public {
        uint256 tokenId = _stakeAndValidate(user, DEFAULT_STAKE_AMOUNT, DEFAULT_LOCK_TIME);
        vm.prank(user);
        vt.approve(other, tokenId);
        vm.prank(other);
        vt.transferFrom(user, other, tokenId);
        vm.stopPrank();
        assertEq(vt.ownerOf(tokenId), other);
    }
}
