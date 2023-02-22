// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IA3SQueue {
    /**
     * @dev Node structure
     *
     * - `prev` previous pointer, point to right.
     * - `next` previous pointer, point to left.
     * - `balance` calculated $A balance: only assigned value when node is pushed out of queue
     * - `inQueueTime` timestamp when pushed into queue.
     * - `outQueueTime` timestamp when pushed out of queue.
     * - `queueStatus` Node status.
     *
     */
    struct Node {
        address addr;
        address prev;
        address next;
        uint256 balance;
        uint64 inQueueTime;
        uint64 outQueueTime;
        queueStatus stat;
    }

    enum queueStatus {
        INQUEUE,
        PENDING,
        CLAIMED,
        STOLEN
    }

    /**
     * @dev Operation purpose: Manually turn on/off the queue to allow PushOut
     *
     * Requirements:
     * - `msg.sender` must be owner
     *
     */
    function lockQueue() external;

    /**
     * @dev see lockQueue90
     */
    function unlockQueue() external;

    /**
     * @dev Get the actual head in queue (ignoring status)
     * Requirements:
     * - `msg.sender` must be owner
     */
    function getGloabalHead() external view returns (address);

    /**
     * @dev Get the next node of '_addr'
     * Requirements:
     * - `msg.sender` must be owner
     */
    function getNext(address _addr) external view returns (address);

    /**
     * @dev Get the prev node of '_addr'
     * Requirements:
     * - `msg.sender` must be owner
     */
    function getPrev(address _addr) external view returns (address);

    /**
     * @dev Get the status of node '_addr'
     */
    function getStat(address _addr) external view returns (queueStatus);

    /**
     * @dev Get the token amount(available to mint) of node '_addr'
     */
    function getTokenAmount(address _addr) external view returns (uint256);

    /**
     * @dev Push Node into queue, initiate the Node status
     *      Calculate the today's in queue count 'todayInQueueCount', previous day's in queue count 'preDayInQueueCount'
     *      Extend the Maxium queue Length 'maxQueueLength' based on previous day's in queue count
     *      If the current queue length 'curQueueLength' exceed the maximum queue length - Push Out the head node
     *
     * Requirements:
     *
     * - `_addr` must not be O address.
     * - `_addr` must be 1st time play: address_node[_addr].addr == address(0)
     * - `_addr` must be a valid A3S address: Address tokenId not to be 0.
     *
     * Emits a {Push In} event.
     */
    function pushIn(address _addr) external;

    /**
     * @dev Put 'jumpingAddr' to queue tail, Steal the 'stolenAddr' $A
     *
     * Requirements:
     *
     * - `jumpingAddr` & 'stolenAddr' must not be O address.
     * Separately Emits a {JumpToTail} and {Steal} event.
     */
    function jumpToSteal(address jumpingAddr, address stolenAddr) external;

    /**
     * @dev Put 'jumpingAddr' to queue tail
     *
     * Requirements:
     *
     * - `jumpingAddr` must not be O address.
     * Emits a {JumpToTail} event.
     */
    function jumpToTail(address jumpingAddr) external;

    /**
     * @dev Get Node's current position
     *      Starting from 1, if not in queue return 0;
     *
     * Requirements:
     *
     * - `_addr` must not be O address.
     *
     */
    function getCurrentPosition(address _addr) external view returns (uint256);

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
    function mint(address _addr) external;

    /**
     * @dev Batch Mint the $A for all the address of current owner
     */
    function batchMint(address[] memory _addr) external;

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

    event Log(string message);
}
