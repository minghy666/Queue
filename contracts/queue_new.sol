// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

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
 *   # Design Idea:
 *   # Everything starts from queue unlock event 
 *   # Once queue got unlocked 
 *   # - get the count down time for pushed out Nodes (for after 5 days stolen)
 *   # - get the token amount for the nodes which need to be pushed out for queue 
 *   # - set the Addess able to be cliams
 *   # - Claim function (require 1: able to claim, 2: time < 5 days from count down)
 *   # - QUESTION? when unlocked queue, what is there is new nodes continue being pushed out of queue?
 */
contract newQueue{
    struct Node{
        address addr;
        //uint256 nodeId; // nodeId = index(position) in array
        address prev;
        address next;
        uint64 balance;
        uint64 mintedTime;
        bool isInQueue;

        bool isAbletoClaim; 
        bool isClaimed;
        uint32 id;
    }

    struct Node_Pushout{
        address addr;
        uint64 balance;
        uint64 claimCountDown;
        bool isAbletoClaim; 
        bool isClaimed;
    }

    //keep track of the A3S address's position in mapping
    mapping(address => Node) address_node; 
    //keep track of pushed out nodes which may need to be stolen
    //mapping(address => Node) address_node_pushout;
    Node_Pushout[] node_pushout;

    //Queue head position
    address headIdx;

    //Queue tail position
    address tailIdx;

    //Maximum Queue Length temp default set to 1000
    uint64 maxQueueLength;

    //Current Queue Lenght
    uint64 curQueueLength;

    //All A3S address count, representing currentID
    uint32 public totalMintedCount;

    //Queue lock - to claim AS token 
    bool public queuelocked;

    uint32[16] private _fibonacci;

    constructor(){
        headIdx = address(0);
        tailIdx = address(0);
        maxQueueLength = 1000;
        curQueueLength = 0;
        _fibonacci = [1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597];
    }

    function pushToQueue(address _addr, uint64 _balance) public{
        require(_addr != address(0), "invalid address");
        require(_balance >= 0, "invalid balance");

        if(headIdx == address(0)){
            address_node[_addr] = Node({
                        addr: _addr,
                        balance: _balance,
                        mintedTime: uint64(block.timestamp),
                        //nodeId: queueItems.length,
                        prev: _addr,
                        next: _addr,
                        isInQueue: true,
                        isAbletoClaim: false,
                        isClaimed: false,
                        id: totalMintedCount
                    });
            headIdx = _addr;
            tailIdx = _addr;
        }else{
            address_node[_addr] = Node({
                    addr: _addr,
                    balance: _balance,
                    mintedTime: uint64(block.timestamp),
                    //nodeId: queueItems.length,
                    prev: address(0),
                    next: tailIdx,
                    isInQueue: true,
                    isAbletoClaim: false,
                    isClaimed: false,
                    id: totalMintedCount
                });

            //Update the next node
            address_node[tailIdx].prev = _addr;
            tailIdx = _addr;
        }
        curQueueLength += 1;

        totalMintedCount += 1;
    }

    function jumpToTail(address _addr) public{
        //If current node is head
        if(_addr == headIdx){
            //Update the new head nodes
            address_node[address_node[_addr].prev].next = address(0);
            headIdx = address_node[_addr].prev;
        }else{
            //Update the neighbor nodes
            address_node[address_node[_addr].next].prev = address_node[_addr].prev;
            address_node[address_node[_addr].prev].next = address_node[_addr].next;
        }
        //Update the next and prev node
        address_node[_addr].next = tailIdx;
        address_node[_addr].prev = address(0);

        //Update previous tail node 
        address_node[tailIdx].prev = _addr; 

        //Update the current tail index
        tailIdx = _addr;
        console.log("Head: ", headIdx);
        console.log("Tail: ", tailIdx);
    }

    function pushOut(uint256 count) public{
        //Update the queun info
        require(count > 0, "Invalid count");
        require(count <= curQueueLength, "exceed the current queue length");

        address startIdx = headIdx;
        for(uint256 i=0; i<count; i++){
            address_node[startIdx].isInQueue = false;
            //Remove the node
            //delete address_node[startIdx];
            //address_node_pushout[startIdx] = address_node[startIdx];
            node_pushout.push(Node_Pushout({
                addr: startIdx,
                balance: uint64(getTokenAmount(startIdx)),
                claimCountDown: uint64(block.timestamp),
                isAbletoClaim: true,
                isClaimed: false
            }));

            delete address_node[startIdx];

            startIdx = address_node[startIdx].prev;
        }

        //Update the headIdx
        headIdx = address_node[startIdx].prev;
        address_node[headIdx].next = address(0);

        //Update current queue length
        curQueueLength -= uint64(count);
    }

    //from Head(0) to it's current position, starting from 0
    function getCurrentPosition(address _addr) public view returns(uint256 ans){
        ans = 0;
        address startIdx = headIdx;
        while(startIdx != _addr){
            ans += 1;
            startIdx = address_node[startIdx].prev;
        }
    }

    //For testing purpose
    function iterateQueue() public view{
        address pointer = headIdx;
        while(pointer != tailIdx){
            console.log("Queue Item Address: ", address_node[pointer].addr);
            pointer = address_node[pointer].prev;
        }
        console.log("Queue Tail Address: ", address_node[pointer].addr);
    }

    function lockQueue() external {
        require(!queuelocked, "A3S: Queue is locked now");
        queuelocked = true;
    }

    function unlockQueue() external {
        require(queuelocked, "A3S: Queue is unlocked now");
        queuelocked = false;
    }

    //Need to run every 24 hours, timer set starts from current timestamp
    function updateQueue() external{
        require(queuelocked = false, "A3S: Queue is locked");
        uint256 claimCountdown = block.timestamp;
        //# of Nodes need to exclude from queue:
        uint256 nodeCountsRemove = _getPrevDayMintedCount(claimCountdown);
        //Push the nodes out of the queue
        pushOut(nodeCountsRemove);
    }

    function getTokenAmount(address _addr) public view returns(uint256 amount){
        //DiffID
        uint128 _diffID = uint128(totalMintedCount - address_node[_addr].id);
        //N: base 10, start from the 1st address, every 1000 address add 1
        uint128 _n = 10 + uint128(totalMintedCount/1000);
        //T: from _fibonacci array
        uint128 _T = 0;
        for(uint256 i=0; i<16; i++){
            if(_fibonacci[i] > address_node[_addr].id){
                _T = _fibonacci[i-1];
            }
        }
        amount = uint256(log_2(uint(_n)) / log_2(uint(_diffID)) * uint128(_T));
    }

    function _getPrevDayMintedCount(uint256 startTimestmp) internal view returns(uint256 count){
        count = 0;
        address pointer = headIdx;
        while(address_node[pointer].mintedTime >= startTimestmp - 1 days && address_node[pointer].mintedTime <= startTimestmp){
            //Unlock to claim
            //address_node[pointer].isAbletoClaim = true;
            pointer = address_node[pointer].prev;
            count += 1;
        }
    }

    function claimToken(address _addr) external {
        for(uint i=0; i<node_pushout.length; i++){
            if(_addr == node_pushout[i].addr){
                require(node_pushout[i].isAbletoClaim, "A3S: Address is not able to claim yet");
                require(!node_pushout[i].isClaimed, "A3S: Token has been claimed");
                //NEED Implement: IERC20.transferFrom(vault, _addr, node.balance);
                //uint64 _balance = node_pushout[i].balance;

                //Remove the node from pushed out queue 
                node_pushout[i] = node_pushout[node_pushout.length - 1];
                node_pushout.pop();
                break;
            }
        }
        
    }

    //Need to run every 24 hours, timer set starts from current timestamp + 5 days 
    function stealToken() external returns(uint64){
        uint64 _balance = 0;
        uint64 counter = 0;
        for(uint256 i=0; i<node_pushout.length; i++){
            if(node_pushout[i].claimCountDown + 5 days <= block.timestamp){
                _balance += node_pushout[i].balance;
                counter += 1;
                node_pushout[i] = node_pushout[node_pushout.length - 1 - i]; 
            }
        }
        for(uint256 j = 0; j<counter; j++){
            node_pushout.pop();
        }
        //NEED Implement: IERC20, transfer from vault to the tailIdx address with 
        return _balance;
    }

    function log_2 (uint x) public pure returns (uint y){
        assembly {
                let arg := x
                x := sub(x,1)
                x := or(x, div(x, 0x02))
                x := or(x, div(x, 0x04))
                x := or(x, div(x, 0x10))
                x := or(x, div(x, 0x100))
                x := or(x, div(x, 0x10000))
                x := or(x, div(x, 0x100000000))
                x := or(x, div(x, 0x10000000000000000))
                x := or(x, div(x, 0x100000000000000000000000000000000))
                x := add(x, 1)
                let m := mload(0x40)
                mstore(m,           0xf8f9cbfae6cc78fbefe7cdc3a1793dfcf4f0e8bbd8cec470b6a28a7a5a3e1efd)
                mstore(add(m,0x20), 0xf5ecf1b3e9debc68e1d9cfabc5997135bfb7a7a3938b7b606b5b4b3f2f1f0ffe)
                mstore(add(m,0x40), 0xf6e4ed9ff2d6b458eadcdf97bd91692de2d4da8fd2d0ac50c6ae9a8272523616)
                mstore(add(m,0x60), 0xc8c0b887b0a8a4489c948c7f847c6125746c645c544c444038302820181008ff)
                mstore(add(m,0x80), 0xf7cae577eec2a03cf3bad76fb589591debb2dd67e0aa9834bea6925f6a4a2e0e)
                mstore(add(m,0xa0), 0xe39ed557db96902cd38ed14fad815115c786af479b7e83247363534337271707)
                mstore(add(m,0xc0), 0xc976c13bb96e881cb166a933a55e490d9d56952b8d4e801485467d2362422606)
                mstore(add(m,0xe0), 0x753a6d1b65325d0c552a4d1345224105391a310b29122104190a110309020100)
                mstore(0x40, add(m, 0x100))
                let magic := 0x818283848586878898a8b8c8d8e8f929395969799a9b9d9e9faaeb6bedeeff
                let shift := 0x100000000000000000000000000000000000000000000000000000000000000
                let a := div(mul(x, magic), shift)
                y := div(mload(add(m,sub(255,a))), shift)
                y := add(y, mul(256, gt(arg, 0x8000000000000000000000000000000000000000000000000000000000000000)))
            }  
    }

}