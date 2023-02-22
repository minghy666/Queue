// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IA3SQueue.sol";
import "../interfaces/IA3SWalletFactoryV3.sol";
import "./libraries/ABDKMathQuad.sol";
import "./libraries/A3SQueueHelper.sol";

contract A3SQueue is IA3SQueue {
    using ABDKMathQuad for uint256;
    using ABDKMathQuad for bytes16;
    //keep track of the A3S address's position in mapping
    mapping(address => Node) address_node;
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
    //Owner addres: owner deploying the contract
    address public owner;
    //A3SFactoryProxy address
    address public A3SWalletFactory;
    //Global queue start time
    uint64 public globalTimer;
    uint16 public preDayInQueueCount;
    uint16 public todayInQueueCount;
    uint16[16] public _fibonacci = [
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

    modifier noZero(address param) {
        require(param != address(0), "A3S: invliad address");
        _;
    }

    modifier ONLY_OWNER(){
        require(msg.sender == owner, "A3S: Access Denied, only owner could call");
        _;
    }

    constructor(
        address _token,
        address _vault,
        address _A3SWalletFactory
    ) {
        headIdx = address(0);
        tailIdx = address(0);
        maxQueueLength = 200;
        curQueueLength = 0;
        token = _token;
        vault = _vault;
        owner = msg.sender;
        globalTimer = uint64(block.timestamp + 1 days);
        preDayInQueueCount = 0;
        queuelocked = false;
        A3SWalletFactory = _A3SWalletFactory;
    }

    /**
     * @dev See {IA3SQueue-lockQueue}.
     */
    function lockQueue() external override ONLY_OWNER {
        require(!queuelocked, "A3S: Queue is locked now");
        queuelocked = true;
    }

    /**
     * @dev See {IA3SQueue-unlockQueue}.
     */
    function unlockQueue() external override ONLY_OWNER{
        require(queuelocked, "A3S: Queue is unlocked now");
        globalTimer = uint64(block.timestamp);
        queuelocked = false;
    }

    /**
     * @dev See {IA3SQueue-getGloabalHead}.
     */
    function getGloabalHead() external view override ONLY_OWNER returns(address) {
        address pointer = headIdx;
        while (address_node[pointer].next != address(0)) {
            pointer = address_node[pointer].next;
        }
        return pointer;
    }

    /**
     * @dev See {IA3SQueue-getNext}.
     */
    function getNext(address _addr) external view override ONLY_OWNER returns (address) {
        return address_node[_addr].next;
    }

    /**
     * @dev See {IA3SQueue-getPrev}.
     */
    function getPrev(address _addr) external view override ONLY_OWNER returns (address) {
        return address_node[_addr].prev;
    }

    /**
     * @dev See {IA3SQueue-getStat}.
     */
    function getStat(address _addr)
        external
        view
        override
        returns (queueStatus)
    {
        return address_node[_addr].stat;
    }

    /**
     * @dev See {IA3SQueue-getTokenAmount}.
     */
    function getTokenAmount(address _addr) external view override returns (uint256) {
        return address_node[_addr].balance;
    }

    /**
     * @dev See {IA3SQueue-pushIn}.
     */
    function pushIn(address _addr) external override noZero(_addr) {
        require(
            address_node[_addr].addr == address(0),
            "A3S: address played and invalid to queue"
        );
        require(
            IA3SWalletFactoryV3(A3SWalletFactory).walletIdOf(_addr) != 0,
            "A3S: address is not a valid A3S address"
        );

        Node memory new_node = Node({
            addr: _addr,
            balance: 0,
            inQueueTime: uint64(block.timestamp),
            prev: address(0),
            next: address(0),
            outQueueTime: 0,
            stat: queueStatus.INQUEUE
        });
        if (headIdx == address(0)) {
            new_node.prev = _addr;
            new_node.next = address(0);
            address_node[_addr] = new_node;
            headIdx = _addr;
            tailIdx = _addr;
        } else {
            new_node.prev = address(0);
            new_node.next = tailIdx;
            address_node[_addr] = new_node;
            //Update the next node
            address_node[tailIdx].prev = _addr;
            tailIdx = _addr;
        }
        curQueueLength += 1;

        //Check the timestamp and update：globalTimer/preDayInQueueCount/todayInQueueCount
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
                uint16 _extended = A3SQueueHelper._getExtendLength(
                    preDayInQueueCount
                );
                maxQueueLength += _extended;
            }
        }
        //WIthin More than 1 day
        //Pre Day in queue is 0, no need to update max length
        //Get today's inqueue from 1
        else {
            globalTimer +=
                (uint64((block.timestamp)) - globalTimer) /
                (60 * 60 * 24);
            preDayInQueueCount = 0;
            todayInQueueCount = 1;
        }
        //Check if Maximum Length reached and Start Push
        if (curQueueLength > maxQueueLength && !queuelocked) {
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

    /**
     * @dev See {IA3SQueue-jumpToSteal}.
     */
    function jumpToSteal(address jumpingAddr, address stolenAddr)
        external
        override
    {
        _jumpToTail(jumpingAddr);
        //Make sure the jumping address is at queue tail
        if (jumpingAddr == tailIdx) {
            _steal(stolenAddr);
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
    function mint(address _addr) external override {
        _mint(_addr);
    }

    /**
     * @dev See {IA3SQueue-batchMint}.
     */
    function batchMint(address[] memory _addr) external override {
        for (uint16 i = 0; i < _addr.length; i++) {
            _mint(_addr[i]);
        }
    }

    /**
     * @dev See {IA3SQueue-getCurrentPosition}.
     */
    function getCurrentPosition(address _addr)
        external
        view
        override
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

    function pushOut() internal {
        //Pushed out the Head Node
        address _cur_addr = headIdx;
        address_node[_cur_addr].stat = queueStatus.PENDING;
        address_node[_cur_addr].outQueueTime = uint64(block.timestamp);
        address_node[_cur_addr].balance = uint256(_getTokenAmount(_cur_addr));
        //Update the headIdx
        headIdx = address_node[headIdx].prev;

        //Update current queue length
        curQueueLength -= 1;
        emit PushedOut(
            _cur_addr,
            address_node[headIdx].outQueueTime,
            headIdx,
            tailIdx,
            curQueueLength
        );
    }

    function _jumpToTail(address _addr) internal noZero(_addr) {
        require(_addr != tailIdx, "A3S: already in queue tail!");
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

    function _steal(address _addr) internal noZero(_addr) returns (uint256) {
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

    function _mint(address _addr) internal {
        //Require minted addrss belongs to msg.sender
        require(
            IA3SWalletFactoryV3(A3SWalletFactory).walletOwnerOf(_addr) ==
                msg.sender,
            "A3S: ONLY owner can mint"
        );
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
        IERC20(token).transferFrom(vault, _addr, _balance);
        address_node[_addr].stat = queueStatus.CLAIMED;

        emit Mint(_addr, _balance);
    }

    function _getTokenAmount(address _addr)
        internal
        view
        returns (uint256 amount)
    {
        uint256 r = 5;
        //Get DiffID
        uint256 _currID = uint256(
            IA3SWalletFactoryV3(A3SWalletFactory).walletIdOf(_addr)
        );
        uint256 _diffID = IA3SWalletFactoryV3(A3SWalletFactory)
            .tokenIdCounter() - _currID;
        //N = 1.1 + 0.1 * ()
        bytes16 _n = A3SQueueHelper._getN(_currID);
        //T: from _fibonacci array
        uint256 _T = 0;
        for (uint256 i = 0; i <= 15; i++) {
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
            .mul(uint256(10**18).fromUInt())
            .mul(_T.fromUInt())
            .mul(r.fromUInt());
        amount = _amount.toUInt();
    }

}
