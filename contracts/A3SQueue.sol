// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IA3SQueue.sol";
import "../interfaces/IA3SWalletFactoryV3.sol";
import "./libraries/ABDKMathQuad.sol";
import "hardhat/console.sol";

/**
 * @title Queue contract
 * @author Mike
 * @dev Functions of the Queue implementation of A3S protocol 
 *   # Design Idea:
 *   # Mappings to store all Nodes [address => Node]
 *   # Linked list to store the actual queue position of each node 
 *   # - prev: previous node's address
 *   # - next: next node's address
 *   # - E.G.
 *   # - Node = [0,1,2,3,4,5,6,7,8,9,10,11,12,13] 
 *   # - Next <- ; prev -> 
 *   # - For Node[2], prev is 3 next is 1
 * @dev Functions of the Queue unlock and Token calculate
 *   # Design key Idea:
 *   # Key events: pushed out, claim, steal, | initial unlock? push and update queue: Every 24 hours; steal: every 24 hours after 3 days of initial unlock
 *   # - Once the nodes are pushed out, the nodes are still in the queue
 *   # - Using the PushedOut timestamp + headIdx to identify the pushed out nodes
 *   # - Calculate the Actual token amount once the Node was pushed out
 *   # - Require {CurrentTime - PushedTime} < 3 days before claim the token 
 *   # - Once calimed the Node will be DELETED from queue 
 *   # - Nodes left (before the headIdx) are the ones not claimed and will be stolen 
 *   # - Once stolen event triggers, iterate through all nodes before the headIdx, calculate the token amount and do transfer to the tailInx address
 *   # - Gas for batch pushout: 1 node: 70K; 3 nodes: 130K; 5 nodes: 200K; 10 nodes: 370K
 *   # - QUESTION? 
 NO NEED TO Replay lifetime ONLY once
 Steal: If in queue, jump to end, if not, just steal
 Steal: 3 days after pushout to queue; once able to steal, not able to claim; steal no time limit
 S.N: queue position
 cRank: tokenID
 Global Rank: total minted address count
 0217
 --------------
 queue status: Never in queue? Test
 pay and call jumptoend who pay?
 steal failure - NOT in queueTail 
 --------------
 */
contract A3SQueue is IA3SQueue {
    using ABDKMathQuad for uint256;
    using ABDKMathQuad for bytes16;
    //keep track of the A3S address's position in mapping
    mapping(address => Node) address_node;
    //keep track of in queue history
    //mapping(address => bool) wasQueued;

    //Queue head position
    address headIdx;

    //Queue tail position
    address tailIdx;

    //Maximum Queue Length temp default set to 1000
    uint64 public maxQueueLength;

    //Current Queue Lenght
    uint64 public curQueueLength;

    //Queue lock - to claim AS token
    bool public queuelocked;

    //All A3S address count, representing currentID
    uint256 public totalMintedCount;

    //Token Address
    address token;

    //Vault Address;
    address vault;

    //Owner addres
    address owner;

    //A3SFactoryProxy address
    address A3SWalletFactory;

    //Jumpe to tail payment
    uint256 jumpingFee;

    //Global start time
    uint64 public globalTimer;
    uint16 public preDayInQueueCount;
    uint16 public todayInQueueCount;

    constructor(address _token, address _vault) {
        headIdx = address(0);
        tailIdx = address(0);
        maxQueueLength = 100;
        curQueueLength = 0;
        totalMintedCount = 9999;
        token = _token;
        vault = _vault;
        owner = msg.sender;
        globalTimer = uint64(block.timestamp + 1 days);
        preDayInQueueCount = 0;
    }

    //get headIdx
    function getHead() external view returns (address) {
        return headIdx;
    }

    //get tailIdx
    function getTail() external view returns (address) {
        return tailIdx;
    }

    //Get the actual head in queue (ignoring status)
    function getGloabalHead() external view returns (address) {
        address pointer = headIdx;
        while (address_node[pointer].next != address(0)) {
            pointer = address_node[pointer].next;
        }

        return pointer;
    }

    //Get next node
    function getNext(address _addr) external view returns (address) {
        return address_node[_addr].next;
    }

    //Get previous node
    function getPrev(address _addr) external view returns (address) {
        return address_node[_addr].prev;
    }

    //Get in queue status
    function getStat(address _addr) external view returns (queueStatus) {
        return address_node[_addr].stat;
    }

    function pushIn(address _addr) external {
        require(_addr != address(0), "A3S: invalid address");
        //require(!wasQueued[_addr], "A3S: address has played before, please unlock the address");
        require(
            address_node[_addr].addr == address(0),
            "A3S: address played and invalid to queue"
        );

        if (headIdx == address(0)) {
            address_node[_addr] = Node({
                addr: _addr,
                balance: 0,
                inQueueTime: uint64(block.timestamp),
                prev: _addr,
                next: address(0),
                id: uint32(curQueueLength) + 1,
                outQueueTime: 0,
                stat: queueStatus.INQUEUE
            });
            headIdx = _addr;
            tailIdx = _addr;
        } else {
            address_node[_addr] = Node({
                addr: _addr,
                balance: 0,
                inQueueTime: uint64(block.timestamp),
                prev: address(0),
                next: tailIdx,
                id: uint32(curQueueLength) + 1,
                outQueueTime: 0,
                stat: queueStatus.INQUEUE
            });

            //Update the next node
            address_node[tailIdx].prev = _addr;
            tailIdx = _addr;
        }
        curQueueLength += 1;

        //Check the timestamp and update timer, today and previous day's inqueue count
        //Within Today
        if (uint64(block.timestamp) <= globalTimer) {
            todayInQueueCount += 1;
        }
        //Within Next Day
        else if (
            uint64(block.timestamp) > globalTimer &&
            uint64((block.timestamp)) - globalTimer <= 1 days
        ) {
            globalTimer += 1 days;
            preDayInQueueCount = todayInQueueCount;
            todayInQueueCount = 1;
            //Update maxQueueLenght based on Previous Day in queue count
            if (preDayInQueueCount >= 200) {
                console.log(
                    "Max length update trigger at: Pre Day inQueue Count is: ",
                    preDayInQueueCount
                );
                uint16 _extended = _getExtendLength(preDayInQueueCount);
                console.log("Extended length added: ", _extended);
                maxQueueLength += _extended;
                console.log("Max queue length updated to: ", maxQueueLength);
            }
        }
        //WIthin More than 1 day
        //Pre Day in queue is 0, no need to update max length
        //Get today's inqueue from 1
        else {
            console.log("No New Incoming in Queue Previous Day");
            globalTimer +=
                (uint64((block.timestamp)) - globalTimer) /
                (60 * 60 * 24);
            preDayInQueueCount = 0;
            todayInQueueCount = 1;
        }
        //Check if Maximum Length reached and Start Push
        if (curQueueLength > maxQueueLength) {
            pushOut();
        }

        emit PushIn(
            _addr,
            address_node[_addr].prev,
            address_node[_addr].next,
            address_node[_addr].inQueueTime,
            headIdx,
            tailIdx,
            curQueueLength
        );
    }

    function jumpToSteal(address jumpingAddr, address stolenAddr) external {
        _jumpToTail(jumpingAddr);
        _steal(stolenAddr);
    }

    function jumpToTail(address jumpingAddr) external {
        _jumpToTail(jumpingAddr);
        emit JumpToTail(jumpingAddr, headIdx, tailIdx, curQueueLength);
    }

    function pushOut() public {
        //Pushed out the Head Node
        address _cur_addr = headIdx;
        address_node[_cur_addr].stat = queueStatus.PENDING;
        address_node[_cur_addr].outQueueTime = uint64(block.timestamp);
        address_node[_cur_addr].balance = uint256(_getTokenAmount(_cur_addr));
        //Update the headIdx
        headIdx = address_node[headIdx].prev;

        //Update current queue length
        curQueueLength -= 1;
        console.log("Node has been pushed out: ", _cur_addr);
        console.log(
            "Out of queue time: ",
            address_node[_cur_addr].outQueueTime
        );
        emit PushedOut(
            _cur_addr,
            address_node[headIdx].outQueueTime,
            headIdx,
            tailIdx,
            curQueueLength
        );
    }

    //from Head(0) to it's current position, starting from 1, if not in queue return 0;
    function getCurrentPosition(address _addr)
        external
        view
        returns (uint256 ans)
    {
        if (address_node[_addr].stat != queueStatus.INQUEUE) {
            return 0;
        }
        ans = 1;
        address startIdx = headIdx;
        while (startIdx != _addr) {
            ans += 1;
            startIdx = address_node[startIdx].prev;
        }
    }

    function mint(address _addr) external {
        //Require minted addrss belongs to msg.sender
        // require(
        //     IA3SWalletFactoryV3().walletOwnerOf(_addr) == msg.sender,
        //     "A3S: ONLY owner can mint"
        // );
        require(
            address_node[_addr].outQueueTime > 0,
            "A3S: NOT valid to calim - not pushed"
        );
        require(
            address_node[_addr].stat == queueStatus.PENDING,
            "A3S: ONLY pending status could be claimed"
        );
        require(
            uint64(block.timestamp) - address_node[_addr].outQueueTime < 3 days,
            "A3S: NOT valid to calim - out of queue exceed 3 days"
        );
        uint256 _balance = address_node[_addr].balance;
        //NEED Implement: token transfer
        //IERC20(token).transferFrom(vault, _addr, address_node[_addr].balance);
        IERC20(token).transferFrom(vault, _addr, 10000);
        address_node[_addr].stat = queueStatus.CLAIMED;

        emit Mint(_addr, _balance);
    }

    function lockQueue() external {
        require(!queuelocked, "A3S: Queue is locked now");
        queuelocked = true;
    }

    function unlockQueue() external {
        require(queuelocked, "A3S: Queue is unlocked now");
        globalTimer = uint64(block.timestamp);
        queuelocked = false;
    }

    function _jumpToTail(address _addr) internal {
        require(_addr != address(0), "A3S: invalid address");
        require(_addr != tailIdx, "A3S: already in queue tail!");
        require(
            IERC20(token).transferFrom(_addr, vault, jumpingFee),
            "A3S: jumping fee not paied"
        );
        //If current node is head
        if (_addr == headIdx) {
            //Update the new head nodes
            address_node[tailIdx].prev = _addr;
            address_node[_addr].next = tailIdx;
            address_node[address_node[_addr].prev].next = address(0);
            headIdx = address_node[_addr].prev;
        } else {
            //Update the neighbor nodes
            address_node[address_node[_addr].next].prev = address_node[_addr]
                .prev;
            address_node[address_node[_addr].prev].next = address_node[_addr]
                .next;
        }
        //Update the next and prev node
        address_node[_addr].next = tailIdx;
        address_node[_addr].prev = address(0);

        //Update previous tail node
        address_node[tailIdx].prev = _addr;

        //Update the current tail index
        tailIdx = _addr;
    }

    function _steal(address _addr) internal returns (uint256) {
        require(_addr != address(0), "A3S: invalid stolen address");
        require(
            address_node[_addr].stat == queueStatus.PENDING,
            "A3S: ONLY pending status could be stolen"
        );
        require(
            uint64(block.timestamp) - address_node[_addr].outQueueTime >=
                3 days,
            "A3S: NOT valid to steal - not reaching 3 days"
        );
        //ERC20 token transfer for _balance;
        uint256 _balance = address_node[_addr].balance;
        IERC20(token).transferFrom(vault, tailIdx, _balance);
        address_node[_addr].balance = 0;
        address_node[_addr].stat = queueStatus.STOLEN;

        emit Steal(tailIdx, _addr, _balance);
        return _balance;
    }

    function _getExtendLength(uint16 prevDayIncreCount)
        public
        pure
        returns (uint16 extendLength)
    {
        uint8[21] memory _index = [
            0,
            18,
            32,
            42,
            50,
            58,
            62,
            67,
            71,
            73,
            77,
            78,
            81,
            82,
            84,
            85,
            86,
            87,
            88,
            89,
            90
        ];
        uint16 n = prevDayIncreCount / 100;
        extendLength = uint16(_index[n - 1]);
    }

    function _getTokenAmount(address _addr)
        internal
        view
        returns (uint256 amount)
    {
        uint256 r = 5;
        uint16[16] memory _fibonacci = [
            1,
            2,
            3,
            5,
            8,
            13,
            21,
            34,
            55,
            89,
            144,
            233,
            377,
            610,
            987,
            1597
        ];
        //Get DiffID
        uint256 _currID = uint256(
            IA3SWalletFactoryV3(A3SWalletFactory).walletIdOf(_addr)
        );
        uint256 _diffID = totalMintedCount - _currID;
        //N = 1.1 + 0.1 * ()
        bytes16 _n = _getN(_currID);
        //T: from _fibonacci array
        uint256 _T = 0;
        for (uint256 i = 0; i <= 16; i++) {
            if (
                ((block.timestamp - address_node[_addr].inQueueTime) / 86400) >=
                _fibonacci[i] &&
                ((block.timestamp - address_node[_addr].inQueueTime) / 86400) <
                _fibonacci[i + 1]
            ) {
                _T = _fibonacci[i];
            }
        }
        bytes16 _amount = ABDKMathQuad
            .log_2(_diffID.fromUInt())
            .div(ABDKMathQuad.log_2(_n))
            .mul(_T.fromUInt())
            .mul(r.fromUInt());
        amount = _amount.toUInt();
    }

    function _getN(uint256 diffID) internal pure returns (bytes16 n) {
        bytes16 m = uint256(11).fromUInt().div(uint256(10).fromUInt());
        bytes16 q = uint256(1).fromUInt().div(uint256(10).fromUInt());
        bytes16 k = uint256(diffID / uint256(100)).fromUInt();
        n = m.add(q.mul(k));
    }

    //For testing purpose
    function iterateQueue() public view {
        address pointer = headIdx;
        while (pointer != tailIdx) {
            console.log("Queue Item Address: ", address_node[pointer].addr);
            pointer = address_node[pointer].prev;
        }
        console.log("Queue Item Address: ", address_node[pointer].addr);
        console.log("current queue length:", curQueueLength);
        console.log("Head Index: ", headIdx);
        console.log("Tail Index: ", tailIdx);
    }
}
