// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IA3SQueue {
    enum queueStatus {
        INQUEUE,
        PENDING,
        CLAIMED,
        STOLEN
    }

    struct Node {
        address addr;
        address prev;
        address next;
        uint256 balance;
        uint64 inQueueTime;
        uint64 outQueueTime;
        uint32 id;
        queueStatus stat;
    }

    function getHead() external view returns (address);

    //get tailIdx
    function getTail() external view returns (address);

    //Get the actual head in queue (ignoring status)
    function getGloabalHead() external view returns (address);

    //Get next node
    function getNext(address _addr) external view returns (address);

    //Get previous node
    function getPrev(address _addr) external view returns (address);

    //Get in queue status
    function getStat(address _addr) external view returns (queueStatus);

    function pushIn(address _addr) external;

    function jumpToSteal(address jumpingAddr, address stolenAddr) external;

    function jumpToTail(address jumpingAddr) external;

    //from Head(0) to it's current position, starting from 1, if not in queue return 0;
    function getCurrentPosition(address _addr) external view returns (uint256);

    function mint(address _addr) external;

    function lockQueue() external;

    function unlockQueue() external;

    //For Testing use 
    function iterateQueue() external view;

    event PushIn(
        address addr,
        address prev,
        address next,
        uint64 inQueueTime,
        address headIdx,
        address tailIdx,
        uint64 curQueueLength
    );

    event JumpToTail(address jumpingAddr, address headIdx, address tailIdx, uint64 curQueueLength);

    event Steal(address stealAddr, address stolenAddr, uint256 amount);

    event PushedOut(
        address pushedOutAddr,
        uint64 outQueueTime,
        address headIdx,
        address tailIdx,
        uint64 curQueueLength
    );

    event Mint(address addr, uint256 claimedAmount);
}
