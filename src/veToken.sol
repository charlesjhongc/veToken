// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import { IveToken } from "./interfaces/IveToken.sol";
import { Ownable } from "./Ownable.sol";

contract veToken is IveToken, ERC721, Ownable, ReentrancyGuard {
    uint256 public constant PENALTY_RATE_PRECISION = 10000;
    uint256 private constant WEEK = 1 weeks;
    address public immutable token;
    address public dstToken;
    bool public conversion = false;

    uint256 public tokenSupply;
    uint256 public epoch;
    uint256 public maxLockDuration = 365 days;
    uint256 public earlyWithdrawPenaltyRate = 3000;

    mapping(uint256 => Point) public poolPointHistory; // epoch -> point
    mapping(uint256 => Point[1000000000]) public userPointHistory; // user -> Point[user_epoch]
    mapping(uint256 => LockedBalance) public locked; // tokenId -> locked balance
    mapping(uint256 => uint256) public userPointEpoch; // tokenId -> epoch
    mapping(uint256 => int256) public dRateChanges; // time -> signed declining rate change
    mapping(uint256 => uint256) public ownershipChange; // tokenId -> block number

    /// @dev Current count of token
    uint256 internal tokenId;

    /// @notice Contract constructor
    /// @param _owner owner address
    /// @param _tokenAddr token address
    constructor(address _owner, address _tokenAddr) ERC721("veToken NFT", "veToken") Ownable(_owner) {
        token = _tokenAddr;

        poolPointHistory[0].blk = block.number;
        poolPointHistory[0].ts = block.timestamp;
    }

    function vBalanceOf(uint256 _tokenId) external view override returns (uint256) {
        return _vBalanceOfAtTime(_tokenId, block.timestamp);
    }

    function vBalanceOfAtTime(uint256 _tokenId, uint256 _t) external view override returns (uint256) {
        require(_t <= block.timestamp, "Invalid timestamp");
        return _vBalanceOfAtTime(_tokenId, _t);
    }

    /// @notice Get the current voting power for `_tokenId`
    /// @param _tokenId NFT for lock
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function _vBalanceOfAtTime(uint256 _tokenId, uint256 _t) private view returns (uint256) {
        if (ownershipChange[_tokenId] == block.number) return 0;
        Point memory lastPoint;

        uint256 _epoch = userPointEpoch[_tokenId];
        if (_epoch == 0) {
            return 0;
        } else {
            // search for the userEpoch where _t is bigger then userPointHistory[_tokenId][_epoch].ts,
            // but smaller then userPointHistory[_tokenId][_epoch+1].ts
            for (uint256 i = _epoch; i > 0; i--) {
                lastPoint = userPointHistory[_tokenId][i];
                if (lastPoint.ts <= _t) {
                    break;
                }
            }
        }

        lastPoint.vBalance -= lastPoint.decliningRate * (int256(_t) - int256(lastPoint.ts));
        if (lastPoint.vBalance < 0) {
            lastPoint.vBalance = 0;
        }
        return uint256(lastPoint.vBalance);
    }

    function vBalanceOfAtBlk(uint256 _tokenId, uint256 _block) external view override returns (uint256) {
        require(_block <= block.number, "Invalid block number");

        // Binary search
        uint256 _min = 0;
        uint256 _max = userPointEpoch[_tokenId];
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[_tokenId][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        Point memory uPoint = userPointHistory[_tokenId][_min];

        uint256 maxEpoch = epoch;
        uint256 _epoch = _findBlockEpoch(_block, maxEpoch);
        Point memory point0 = poolPointHistory[_epoch];
        uint256 dBlock;
        uint256 dt;
        if (_epoch < maxEpoch) {
            Point memory point1 = poolPointHistory[_epoch + 1];
            dBlock = point1.blk - point0.blk;
            dt = point1.ts - point0.ts;
        } else {
            dBlock = block.number - point0.blk;
            dt = block.timestamp - point0.ts;
        }
        uint256 blockTime = point0.ts;
        if (dBlock != 0) {
            blockTime += (dt * (_block - point0.blk)) / dBlock;
        }

        uPoint.vBalance -= uPoint.decliningRate * int256(blockTime - uPoint.ts);
        if (uPoint.vBalance >= 0) {
            return uint256(uPoint.vBalance);
        } else {
            return 0;
        }
    }

    /// @notice Binary search for pool epoch of block number
    /// @param _block Block to find
    /// @param _maxEpoch Don't go beyond this epoch
    /// @return Approximate timestamp for block
    function _findBlockEpoch(uint256 _block, uint256 _maxEpoch) private view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = _maxEpoch;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (poolPointHistory[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    // Binary search for pool epoch of _t
    function _findTimeEpoch(uint256 _t, uint256 _maxEpoch) private view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = _maxEpoch;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (poolPointHistory[_mid].ts <= _t) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function _transfer(address _from, address _to, uint256 _tokenId) internal override {
        // set the block of ownership transfer (for Flash NFT protection)
        ownershipChange[_tokenId] = block.number;
        super._transfer(_from, _to, _tokenId);
    }

    /// @notice Get timestamp when `_tokenId`'s lock finishes
    /// @param _tokenId User NFT
    /// @return Epoch time of the lock end
    function unlockTime(uint256 _tokenId) external view override returns (uint256) {
        return locked[_tokenId].end;
    }

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lock_duration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    function createLock(uint256 _value, uint256 _lockDuration) external override nonReentrant returns (uint256) {
        return _createLock(_value, _lockDuration, msg.sender);
    }

    /// @notice Deposit `_value` tokens for `_to` and lock for `_lock_duration`.
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to The owner of NFT
    function createLockFor(uint256 _value, uint256 _lockDuration, address _to) external override nonReentrant returns (uint256) {
        return _createLock(_value, _lockDuration, _to);
    }

    function _createLock(uint256 _value, uint256 _lockDuration, address _to) internal returns (uint256) {
        require(_value > 0, "Zero lock amount");

        // unlockTime is rounded down to weeks
        uint256 _unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK;
        require(_unlockTime > block.timestamp, "Lock duration too short");
        require(_unlockTime <= block.timestamp + maxLockDuration, "Unlock time exceed maximun");

        ++tokenId;
        uint256 _tokenId = tokenId;
        _safeMint(_to, _tokenId);
        _depositFor(_tokenId, _value, _unlockTime, locked[_tokenId], DepositType.CREATE_LOCK_TYPE);
        return _tokenId;
    }

    /// @notice Deposit `_value` tokens for `_tokenId` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param _tokenId lock NFT
    /// @param _value Amount to add to user's lock
    function depositFor(uint256 _tokenId, uint256 _value) external override nonReentrant {
        require(_value > 0, "Zero deposit amount");

        LockedBalance memory _locked = locked[_tokenId];
        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to expired lock");
        _depositFor(_tokenId, _value, 0, _locked, DepositType.INCREASE_LOCK_AMOUNT);
    }

    /// @notice Extend the unlock time for `_tokenId`
    /// @param _tokenId lock NFT
    /// @param _lockDuration New number of seconds until tokens unlock
    function extendLock(uint256 _tokenId, uint256 _lockDuration) external override nonReentrant {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved or owner");

        LockedBalance memory _locked = locked[_tokenId];
        require(_locked.end > block.timestamp, "Lock expired");
        require(_locked.amount > 0, "Nothing is locked");

        uint256 _unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK;
        require(_unlockTime > _locked.end, "Can only increase lock duration");
        require(_unlockTime <= block.timestamp + maxLockDuration, "Unlock time exceed maximun");

        _depositFor(_tokenId, 0, _unlockTime, _locked, DepositType.INCREASE_UNLOCK_TIME);
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _tokenId NFT that holds lock
    /// @param _value Amount to deposit
    /// @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param _lockedBalance Previous locked amount / timestamp
    /// @param _depositType The type of deposit
    function _depositFor(uint256 _tokenId, uint256 _value, uint256 _unlockTime, LockedBalance memory _lockedBalance, DepositType _depositType) private {
        // update supply and transfer token first, if needed
        uint256 prevSupply = tokenSupply;
        if (_value != 0 && _depositType != DepositType.MERGE_TYPE) {
            tokenSupply = prevSupply + _value;
            emit Supply(prevSupply, tokenSupply);
            assert(IERC20(token).transferFrom(msg.sender, address(this), _value));
        }

        // update user locked balance
        LockedBalance memory _oldLocked = LockedBalance(_lockedBalance.amount, _lockedBalance.end);
        _lockedBalance.amount += _value;
        if (_unlockTime != 0) {
            _lockedBalance.end = _unlockTime;
        }
        locked[_tokenId] = _lockedBalance;

        // Possibilities:
        // Both _oldLocked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _updateLockedPoint(_tokenId, _oldLocked, _lockedBalance);

        emit Deposit(msg.sender, _tokenId, _value, _lockedBalance.end, _depositType, block.timestamp);
    }

    /// @notice Withdraw all tokens for `_tokenId`
    /// @param _tokenId NFT that holds lock
    function withdraw(uint256 _tokenId) external override nonReentrant {
        address owner = ownerOf(_tokenId);
        _withdrawTo(_tokenId, false, owner);
    }

    /// @notice Withdraw all tokens for `_tokenId` and allow penalty if not expired yet
    /// @param _tokenId NFT that holds lock
    function withdrawEarly(uint256 _tokenId) external override nonReentrant {
        address owner = ownerOf(_tokenId);
        _withdrawTo(_tokenId, true, owner);
    }

    function _withdrawTo(uint256 _tokenId, bool _allowPenalty, address _dstAddress) private {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved or owner");

        uint256 prevSupply = tokenSupply;
        LockedBalance memory _locked = locked[_tokenId];
        uint256 amount = _locked.amount;
        bool expired = block.timestamp >= _locked.end;
        require(expired || _allowPenalty, "Lock has not ended");

        locked[_tokenId] = LockedBalance(0, 0);
        tokenSupply = tokenSupply - amount;

        _updateLockedPoint(_tokenId, _locked, LockedBalance(0, 0));

        // Burn the NFT
        _burn(_tokenId);

        uint256 penalty = 0;
        if (!expired) {
            penalty = (amount * earlyWithdrawPenaltyRate) / PENALTY_RATE_PRECISION;
            amount = amount - penalty;
            // FIXME burn or transfer the penalty
        }
        require(IERC20(token).transfer(_dstAddress, amount), "Token withdraw failed");

        emit Withdraw(msg.sender, expired, _tokenId, amount, penalty, block.timestamp);
        emit Supply(prevSupply, tokenSupply);
    }

    /// @notice Merge two locking NFTs as one
    /// @param _from NFT that holds lock and to be burned
    /// @param _to NFT that holds lock and to be updated
    function merge(uint256 _from, uint256 _to) external override {
        require(_from != _to, "Same NFT ids");
        require(_isApprovedOrOwner(msg.sender, _from), "Not approved or owner of from");
        require(_isApprovedOrOwner(msg.sender, _to), "Not approved or owner of to");

        LockedBalance memory _lockedFrom = locked[_from];
        LockedBalance memory _lockedTo = locked[_to];
        uint256 value0 = _lockedFrom.amount;
        uint256 end = _lockedFrom.end >= _lockedTo.end ? _lockedFrom.end : _lockedTo.end;

        locked[_from] = LockedBalance(0, 0);
        _updateLockedPoint(_from, _lockedFrom, LockedBalance(0, 0));
        _burn(_from);
        _depositFor(_to, value0, end, _lockedTo, DepositType.MERGE_TYPE);
    }

    /// @notice Record global and per-user data to storage
    /// @param _tokenId NFT token ID
    /// @param _oldLocked Pevious locked amount / end lock time for the user, to be replaced by new one
    /// @param _newLocked New locked amount / end lock time for the user
    function _updateLockedPoint(uint256 _tokenId, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) private {
        Point memory pointOld;
        Point memory pointNew;
        int256 dSlopeOld = 0;
        int256 dSlopeNew = 0;
        uint256 _epoch = epoch;

        // Calculate decliningRates and vBalances
        // Kept at zero if not active anymore
        if (_lockIsActive(_oldLocked)) {
            pointOld.decliningRate = int256(_oldLocked.amount / maxLockDuration);
            pointOld.vBalance = pointOld.decliningRate * int256(_oldLocked.end - block.timestamp);
        }
        if (_lockIsActive(_newLocked)) {
            pointNew.decliningRate = int256(_newLocked.amount / maxLockDuration);
            pointNew.vBalance = pointNew.decliningRate * int256(_newLocked.end - block.timestamp);
        }

        // Read values of scheduled changes in the decliningRate
        // old_locked.end can be in the past (expired and withdraw) and in the future (deposit more or extend lock)
        // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
        dSlopeOld = dRateChanges[_oldLocked.end];
        if (_newLocked.end != 0) {
            if (_newLocked.end == _oldLocked.end) {
                dSlopeNew = dSlopeOld;
            } else {
                dSlopeNew = dRateChanges[_newLocked.end];
            }
        }

        Point memory poolLastPoint = Point({ vBalance: 0, decliningRate: 0, ts: block.timestamp, blk: block.number });
        if (_epoch > 0) {
            poolLastPoint = poolPointHistory[_epoch];
        }

        (poolLastPoint, _epoch) = _syncGlobalPoints(poolLastPoint, _epoch);

        // If user last point was in this block, the decliningRate change has been applied already
        // But in such case we have 0 decliningRate(s)
        poolLastPoint.decliningRate += (pointNew.decliningRate - pointOld.decliningRate);
        poolLastPoint.vBalance += (pointNew.vBalance - pointOld.vBalance);
        if (poolLastPoint.decliningRate < 0) {
            poolLastPoint.decliningRate = 0;
        }
        if (poolLastPoint.vBalance < 0) {
            poolLastPoint.vBalance = 0;
        }

        // Record the changed point into history
        poolPointHistory[_epoch] = poolLastPoint;
        // Sync storage variable now
        epoch = _epoch;

        // Schedule the decliningRate changes (decliningRate is going down)
        // We subtract new_user_decliningRate from [_newLocked.end]
        // and add old_user_decliningRate to [_oldLocked.end]
        if (_oldLocked.end > block.timestamp) {
            // dSlopeOld was <something> - pointOld.decliningRate, so we cancel that
            dSlopeOld += pointOld.decliningRate;
            if (_newLocked.end == _oldLocked.end) {
                dSlopeOld -= pointNew.decliningRate; // It was a new deposit, not extension
            }
            dRateChanges[_oldLocked.end] = dSlopeOld;
        }

        if (_newLocked.end > block.timestamp) {
            if (_newLocked.end > _oldLocked.end) {
                dSlopeNew -= pointNew.decliningRate; // old decliningRate disappeared at this point
                dRateChanges[_newLocked.end] = dSlopeNew;
            }
            // else: we recorded it already in dSlopeOld
        }
        // Now handle user history
        uint256 user_epoch = userPointEpoch[_tokenId] + 1;

        userPointEpoch[_tokenId] = user_epoch;
        pointNew.ts = block.timestamp;
        pointNew.blk = block.number;
        userPointHistory[_tokenId][user_epoch] = pointNew;
    }

    // Go over weeks to fill history and calculate what the current pool point is
    function _syncGlobalPoints(Point memory poolLastPoint, uint256 _epoch) private returns (Point memory, uint256) {
        // storedPoolLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory storedPoolLastPoint = Point({ vBalance: 0, decliningRate: 0, ts: poolLastPoint.ts, blk: poolLastPoint.blk });

        // avgBlktime = dTime/dBlock
        // If last point is already recorded in this block, avgBlkTime=0
        // But that's ok because we know the block in such case
        uint256 avgBlkTime = 0;
        if (block.number > storedPoolLastPoint.blk) {
            avgBlkTime = (block.timestamp - storedPoolLastPoint.ts) / (block.number - storedPoolLastPoint.blk);
        }

        uint256 lastPointTs = poolLastPoint.ts;
        uint256 nextPointTs = ((lastPointTs / WEEK) * WEEK) + WEEK;

        // Assume it won't exceed 255 weeks since last time pool point updated.
        // If it does, users will be able to withdraw but vote weight will be broken
        for (uint256 i = 0; i < 255; ++i) {
            int256 dSlope = 0;
            if (nextPointTs > block.timestamp) {
                nextPointTs = block.timestamp;
            } else {
                dSlope = dRateChanges[nextPointTs];
            }

            // update decliningRate and vBalance
            poolLastPoint.vBalance -= poolLastPoint.decliningRate * (int256(nextPointTs - lastPointTs));
            poolLastPoint.decliningRate += dSlope;
            if (poolLastPoint.vBalance < 0) {
                // This can happen
                poolLastPoint.vBalance = 0;
            }
            if (poolLastPoint.decliningRate < 0) {
                // This cannot happen - just in case
                poolLastPoint.decliningRate = 0;
            }

            // update ts and block (approximately block number)
            poolLastPoint.ts = nextPointTs;
            if (avgBlkTime > 0) {
                poolLastPoint.blk = storedPoolLastPoint.blk + (nextPointTs - storedPoolLastPoint.ts) / avgBlkTime;
            } else {
                poolLastPoint.blk = storedPoolLastPoint.blk;
            }

            // record or return last point
            _epoch += 1;
            if (nextPointTs == block.timestamp) {
                // overwrite to exact block.number if possible (at the last point)
                poolLastPoint.blk = block.number;
                // return poolLastPoint, may be adjusted by caller and saved into storage using new epoch index
                return (poolLastPoint, _epoch);
            } else {
                poolPointHistory[_epoch] = poolLastPoint;
            }

            // move time window and continue
            lastPointTs = nextPointTs;
            nextPointTs += WEEK;
        }

        // should not reach here
        revert();
    }

    function _lockIsActive(LockedBalance memory lock) private view returns (bool) {
        return lock.end > block.timestamp && lock.amount > 0;
    }

    function totalvBalance() external view override returns (uint256) {
        return _totalvBalanceAt(poolPointHistory[epoch], block.timestamp);
    }

    /// @notice Calculate total voting power
    /// @dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
    /// @return Total voting power
    function totalvBalanceAtTime(uint256 t) public view override returns (uint256) {
        require(t <= block.timestamp, "Invalid timestamp");
        uint256 targetEpoch = _findTimeEpoch(t, epoch);
        return _totalvBalanceAt(poolPointHistory[targetEpoch], t);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _block Block to calculate the total voting power at
    /// @return Total voting power at `_block`
    function totalvBalanceAtBlk(uint256 _block) external view override returns (uint256) {
        require(_block <= block.number, "Invalid block number");
        uint256 _epoch = epoch;
        uint256 targetEpoch = _findBlockEpoch(_block, _epoch);

        Point memory point = poolPointHistory[targetEpoch];
        uint256 dt = 0;
        if (targetEpoch < _epoch) {
            Point memory pointNext = poolPointHistory[targetEpoch + 1];
            if (point.blk != pointNext.blk) {
                dt = ((_block - point.blk) * (pointNext.ts - point.ts)) / (pointNext.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                dt = ((_block - point.blk) * (block.timestamp - point.ts)) / (block.number - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point
        return _totalvBalanceAt(point, point.ts + dt);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param point The point (vBalance/decliningRate) to start search from
    /// @param t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function _totalvBalanceAt(Point memory point, uint256 t) private view returns (uint256) {
        Point memory lastPoint = point;
        uint256 pointTime = (lastPoint.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            pointTime += WEEK;
            int256 dRateChange = 0;
            if (pointTime > t) {
                pointTime = t;
            } else {
                dRateChange = dRateChanges[pointTime];
            }
            lastPoint.vBalance -= lastPoint.decliningRate * int256(pointTime - lastPoint.ts);
            if (pointTime == t) {
                break;
            }
            lastPoint.decliningRate += dRateChange;
            lastPoint.ts = pointTime;
        }

        if (lastPoint.vBalance < 0) {
            lastPoint.vBalance = 0;
        }
        return uint256(lastPoint.vBalance);
    }
}
