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
 */
contract newQueue{

    struct Node{
        address addr;
        //uint256 nodeId; // nodeId = index(position) in array
        address prev;
        address next;
        uint64 balance;
        uint64 queueTime;
        bool isInQueue;
    }

    //keep track of the A3S address's position in Array
    mapping(address => Node) address_node; 

    //Queue head position
    address headIdx;

    //Queue tail position
    address tailIdx;

    //Maximum Queue Length temp default set to 1000
    uint64 maxQueueLength;

    //Current Queue Lenght
    uint64 curQueueLength;

    constructor(){
        headIdx = address(0);
        tailIdx = address(0);
        maxQueueLength = 1000;
        curQueueLength = 0;
    }

    function pushToQueue(address _addr, uint64 _balance) public{
        require(_addr != address(0), "invalid address");
        require(_balance >= 0, "invalid balance");

        if(headIdx == address(0)){
            address_node[_addr] = Node({
                        addr: _addr,
                        balance: _balance,
                        queueTime: uint64(block.timestamp),
                        //nodeId: queueItems.length,
                        prev: _addr,
                        next: _addr,
                        isInQueue: true
                    });
            headIdx = _addr;
            tailIdx = _addr;
        }else{
            address_node[_addr] = Node({
                    addr: _addr,
                    balance: _balance,
                    queueTime: uint64(block.timestamp),
                    //nodeId: queueItems.length,
                    prev: address(0),
                    next: tailIdx,
                    isInQueue: true
                });

            //Update the next node
            address_node[tailIdx].prev = _addr;
            tailIdx = _addr;
        }
        curQueueLength += 1;
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
            startIdx = address_node[startIdx].prev;
            //Remove the node
            delete address_node[startIdx];
        }

        //Update the headIdx
        headIdx = address_node[startIdx].prev;
        address_node[headIdx].next = address(0);

        //Update current queue length
        curQueueLength -= uint64(count);
    }

    //from Head(0) to it's current position, starting from 0
    function getCurrentPosition(address _addr) public view returns(uint256){
        uint256 ans = 0;
        address startIdx = headIdx;
        while(startIdx != _addr){
            ans += 1;
            startIdx = address_node[startIdx].prev;
        }
        return ans;
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
}