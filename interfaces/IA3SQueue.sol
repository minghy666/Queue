// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../contracts/libraries/A3SQueueHelper.sol";

interface IA3SQueue {
    /**
     * @dev Operation purpose: Manually turn on/off the queue to allow PushOut
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function lockQueue() external;

    /**
     * @dev same as lockQueue()
     */
    function unlockQueue() external;

    /**
     * @dev Operation purpose: update the locking days, default is 3 days
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function updateLockingDays(uint16 newlockingDays) external;

    /**
     * @dev Operation purpose: update the Maximum Queue Length, default is 300
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function updateMaxQueueLength(uint64 maximumQL) external;

    /**
     * @dev Push Node into queue, initiate the Node status
     *      Calculate the today's in queue count 'todayInQueueCount', previous day's in queue count 'preDayInQueueCount'
     *      Extend the Maxium queue Length 'maxQueueLength' based on previous day's in queue count
     *      If the current queue length 'curQueueLength' exceed the maximum queue length - Push Out the head node
     *
     * Requirements:
     *
     * - `_addr` must not be O address.
     * - `_addr` must be 1st time play: addressNode[_addr].addr == address(0)
     * - `_addr` must be a valid A3S address: Address tokenId not to be 0.
     *
     * Emits a {Push In} event.
     */
    function pushIn(address addr) external;

    /**
     * @dev Put 'jumpingAddr' to queue tail, Steal the 'stolenAddr' $A
     *
     * Requirements:
     *
     * - `jumpingAddr` & 'stolenAddr' must not be O address.
     *
     * Separately Emits a {JumpToTail} and {Steal} event.
     */
    function jumpToSteal(address jumpingAddr, address stolenAddr) external;

    /**
     * @dev Put 'jumpingAddr' to queue tail
     *
     * Requirements:
     *
     * - `jumpingAddr` must not be O address.
     *
     * Emits a {JumpToTail} event.
     */
    function jumpToTail(address jumpingAddr) external;

    /**
     * @dev Mint the $A for the address
     *      calling IERC20 transferFrom(valut, _addr, tokenAmount)
     *
     * Requirements:
     *
     * - `_addr` must not be O address.
     * - '_addr''s walletOwnerOf must be msg.sender - ONLY owner could mint $A
     *
     * Emits a {Mint} event.
     */
    function mint(address addr) external;

    /**
     * @dev Batch Mint the $A for all the address of current owner
     */
    function batchMint(address[] memory addr) external;

    /**
     * @dev Events definition
     */
    event PushIn(
        address addr,
        address prev,
        address next,
        uint64 inQueueTime,
        address headIdx,
        address tailIdx,
        uint64 curQueueLength
    );

    event JumpToTail(
        address jumpingAddr,
        address headIdx,
        address tailIdx,
        uint64 curQueueLength
    );

    event Steal(address stealAddr, address stolenAddr, uint256 amount);

    event PushedOut(
        address pushedOutAddr,
        uint64 outQueueTime,
        address headIdx,
        address tailIdx,
        uint64 curQueueLength
    );

    event Mint(address addr, uint256 mintAmount);

    event UpdateLockingDays(uint16 newlockingDays, address tokenAddress);
}
