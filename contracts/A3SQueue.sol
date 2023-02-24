// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IA3SQueue.sol";
import "../interfaces/IA3SWalletFactoryV3.sol";
import "./libraries/A3SQueueHelper.sol";

contract A3SQueue is IA3SQueue, Ownable {
    //keep track of the A3S address's position in mapping
    mapping(address => A3SQueueHelper.Node) public addressNode;
    //Queue head position
    address public headIdx;
    //Queue tail position
    address public tailIdx;
    //Maximum Queue Length temp default set to 200
    uint64 public maxQueueLength;
    //Current Queue Lenght
    uint64 public curQueueLength;
    //Queue lock - operation requests, manully control when the queue starts to push
    bool public queuelocked;
    //ERC2- Token Address
    address public token;
    //Vault Address: performing token transfer for Mint and Steal
    address public vault;
    //A3SFactoryProxy address
    address public A3SWalletFactory;
    //Global queue start time
    uint64 public lastDayTimer;
    //New IN Queue count for today
    uint64 public todayInQueueCount;
    //Locking day: default is 3, might be updated in future
    uint16 public lockingDay;

    constructor(
        address _token,
        address _vault,
        address _A3SWalletFactory,
        uint64 _lastDayTimer,
        uint64 _maxQueueLength
    ) {
        token = _token;
        vault = _vault;
        lastDayTimer = _lastDayTimer + 1 days;
        A3SWalletFactory = _A3SWalletFactory;
        lockingDay = 3;
        maxQueueLength = _maxQueueLength;
    }

    /**
     * @dev See {IA3SQueue-lockQueue}.
     */
    function lockQueue() external override onlyOwner {
        require(!queuelocked, "A3S: Queue is locked now");
        queuelocked = true;
    }

    /**
     * @dev See {IA3SQueue-unlockQueue}.
     */
    function unlockQueue() external override onlyOwner {
        require(queuelocked, "A3S: Queue is unlocked now");
        lastDayTimer = uint64(block.timestamp);
        queuelocked = false;
    }

    /**
     * @dev See {IA3SQueue-updateLockingDays}.
     */
    function updateLockingDays(uint16 newlockingDays)
        external
        override
        onlyOwner
    {
        lockingDay = newlockingDays;
        emit UpdateLockingDays(newlockingDays, token);
    }

    /**
     * @dev See {IA3SQueue-updateMaxQueueLength}.
     */
    function updateMaxQueueLength(uint64 maximumQL)
        external
        override
        onlyOwner
    {
        maxQueueLength = maximumQL;
    }
    
    /**
     * @dev See {IA3SQueue-pushIn}.
     */
    function pushIn(address addr) external override {
        require(addr != address(0));
        require(
            addressNode[addr].addr == address(0),
            "A3S: address played and invalid to queue"
        );
        require(
            IA3SWalletFactoryV3(A3SWalletFactory).walletIdOf(addr) != 0,
            "A3S: address is not a valid A3S address"
        );
        require(
            IA3SWalletFactoryV3(A3SWalletFactory).walletOwnerOf(addr) ==
                msg.sender,
            "A3S: ONLY wallet owner could push in"
        );

        A3SQueueHelper.Node memory new_node = A3SQueueHelper.Node({
            addr: addr,
            balance: 0,
            inQueueTime: uint64(block.timestamp),
            prev: address(0),
            next: address(0),
            outQueueTime: 0,
            stat: A3SQueueHelper.queueStatus.INQUEUE
        });
        if (headIdx == address(0)) {
            new_node.prev = addr;
            new_node.next = address(0);
            addressNode[addr] = new_node;
            headIdx = addr;
            tailIdx = addr;
        } else {
            new_node.prev = address(0);
            new_node.next = tailIdx;
            addressNode[addr] = new_node;
            //Update the next node
            addressNode[tailIdx].prev = addr;
            tailIdx = addr;
        }
        curQueueLength += 1;

        //Check the timestamp and update：lastDayTimer/preDayInQueueCount/todayInQueueCount
        //Within Today
        if (uint64(block.timestamp) <= lastDayTimer) {
            todayInQueueCount += 1;
        }
        //Within Next Day
        else if (
            uint64(block.timestamp) > lastDayTimer &&
            uint64((block.timestamp)) - lastDayTimer <= 1 days
        ) {
            lastDayTimer += 1 days;
            //previous day in Queue Count will set to todayInQueueCount;
            //todayInQueueCount = 1;
            //Update maxQueueLenght based on Previous Day in queue count
            if (todayInQueueCount >= 200) {
                uint64 _extended = A3SQueueHelper._getExtendLength(
                    todayInQueueCount
                );
                maxQueueLength += _extended;
            }
            todayInQueueCount = 1;
        }
        //WIthin More than 1 day
        //Pre Day in queue is 0, no need to update max length
        //Get today's inqueue from 1
        else {
            lastDayTimer +=
                (uint64((block.timestamp)) - lastDayTimer) /
                (60 * 60 * 24);
            //preDayInQueueCount = 0;
            todayInQueueCount = 1;
        }
        //Check if Maximum Length reached and Start Push
        if (curQueueLength > maxQueueLength && !queuelocked) {
            _pushOut();
        }

        emit PushIn(
            addr,
            addressNode[addr].prev,
            addressNode[addr].next,
            addressNode[addr].inQueueTime,
            headIdx,
            tailIdx,
            curQueueLength
        );
    }

    /**
     * @dev See {IA3SQueue-jumpToSteal}.
     */
    function jumpToSteal(address jumpingAddr, address stolenAddr)
        external
        override
    {
        _jumpToTail(jumpingAddr);
        //Make sure the jumping address is at queue tail
        if (jumpingAddr == tailIdx && stolenAddr != address(0)) {
            A3SQueueHelper._steal(
                stolenAddr,
                token,
                tailIdx,
                vault,
                lockingDay,
                addressNode
            );
        }
    }

    /**
     * @dev See {IA3SQueue-jumpToTail}.
     */
    function jumpToTail(address jumpingAddr) external override {
        _jumpToTail(jumpingAddr);
        emit JumpToTail(jumpingAddr, headIdx, tailIdx, curQueueLength);
    }

    /**
     * @dev See {IA3SQueue-mint}.
     */
    function mint(address addr) external override {
        A3SQueueHelper._mint(
            addr,
            token,
            vault,
            A3SWalletFactory,
            lockingDay,
            addressNode
        );
    }

    /**
     * @dev See {IA3SQueue-batchMint}.
     */
    function batchMint(address[] memory addrs) external override {
        for (uint16 i = 0; i < addrs.length; i++) {
            A3SQueueHelper._mint(
                addrs[i],
                token,
                vault,
                A3SWalletFactory,
                lockingDay,
                addressNode
            );
        }
    }

    function _pushOut() internal {
        //Pushed out the Head A3SQueueHelper.Node
        address _cur_addr = headIdx;
        addressNode[_cur_addr].stat = A3SQueueHelper.queueStatus.PENDING;
        addressNode[_cur_addr].outQueueTime = uint64(block.timestamp);
        address payable A3SWalletFactory_payable = payable(A3SWalletFactory);
        addressNode[_cur_addr].balance = uint256(
            A3SQueueHelper._getTokenAmount(
                _cur_addr,
                A3SWalletFactory_payable,
                addressNode
            )
        );
        //Update the headIdx
        headIdx = addressNode[headIdx].prev;

        //Update current queue length
        curQueueLength -= 1;
        emit PushedOut(
            _cur_addr,
            addressNode[headIdx].outQueueTime,
            headIdx,
            tailIdx,
            curQueueLength
        );
    }

    function _jumpToTail(address _addr) internal {
        require(_addr != address(0));
        require(_addr != tailIdx, "A3S: already in queue tail!");
        require(
            IA3SWalletFactoryV3(A3SWalletFactory).walletOwnerOf(_addr) ==
                msg.sender,
            "A3S: ONLY wallet owner could push in"
        );
        //If current node is head
        if (_addr == headIdx) {
            //Update the new head nodes
            addressNode[tailIdx].prev = _addr;
            addressNode[_addr].next = tailIdx;
            addressNode[addressNode[_addr].prev].next = address(0);
            headIdx = addressNode[_addr].prev;
        } else {
            //Update the neighbor nodes
            addressNode[addressNode[_addr].next].prev = addressNode[_addr].prev;
            addressNode[addressNode[_addr].prev].next = addressNode[_addr].next;
        }
        //Update the next and prev node
        addressNode[_addr].next = tailIdx;
        addressNode[_addr].prev = address(0);

        //Update previous tail node
        addressNode[tailIdx].prev = _addr;

        //Update the current tail index
        tailIdx = _addr;
    }
}
