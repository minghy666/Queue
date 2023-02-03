// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "hardhat/console.sol";

/**
 * @title Queue contract
 * @author Mike
 * @dev Functions of the Queue implementation of A3S protocol 
 *   # Design Idea:
 *   # Dynamics array to store all the queue items 
 *   # Once pushed into array, the Nodes' position will not change within the array
 *   # Linked list to store the actual queue position of each node 
 *   # - prev: previous nodeId; 
 *   # - next: next nodeId; 
 *   # - nodeId: the node idx of the array, represent as identifier of the node
 *   # Dynamics Array design
 *   # - Initially Array[0] is queue head, Array[length - 1] is  queue tail
 *   # - Node = [0,1,2,3,4,5,6,7,8,9,10,11,12,13] 
 *   # - next <- ; prev -> 
 *   # - e.g: For Node[2], prev is 3 next is 1
 */
contract queue{
    //keep track of the A3S address's position in Array
    mapping(address => uint256) address_pos; 

    struct Node{
        address addr;
        uint256 nodeId; // nodeId = index(position) in array
        uint256 prev;
        uint256 next;
        uint64 balance;
        uint64 queueTime;
        bool isInQueue;
    }

    //Queue head position
    uint256 headIdx;

    //Queue tail position
    uint256 tailIdx;

    //Position of the last item from the moving batch 
    uint256 breakingIdx;

    Node[] queueItems;

    constructor(){
        headIdx = 0;
        tailIdx = 0;
        breakingIdx = 0; 
    }

    function pushToQueue(address _addr, uint256 _balance) public{
        require(_addr != address(0), "invalid address");
        require(_balance >= 0, "invalid balance");

        if(queueItems.length == 0){
            queueItems.push(
                Node({
                    addr: _addr,
                    balance: _balance,
                    queueTime: block.timestamp,
                    nodeId: queueItems.length,
                    prev: 0,
                    next: 0,
                    isInQueue: true
                })
            );

        }else{
            uint256 _curLength = queueItems.length;
            Node memory preNode = queueItems[tailIdx];

            queueItems.push(
                Node({
                    addr: _addr,
                    balance: _balance,
                    queueTime: block.timestamp,
                    nodeId: _curLength,
                    prev: queueItems.length + 1, //temp since the next pushed one is the node previous 
                    next: preNode.nodeId,
                    isInQueue: true
                })
            );
            //Update the next Node
            queueItems[tailIdx].prev = _curLength;

            tailIdx = _curLength;
        }

        address_pos[_addr] = queueItems.length - 1;
    }

    function jumpToTail(address _addr) public{
        //If current node is head
        if(address_pos[_addr] == headIdx){
            //Update the new head nodes
            queueItems[queueItems[address_pos[_addr]].prev].next = 0;
            headIdx = queueItems[address_pos[_addr]].prev;
        }else{
            //Update the neighbor nodes
            queueItems[queueItems[address_pos[_addr]].next].prev = queueItems[address_pos[_addr]].prev;
            queueItems[queueItems[address_pos[_addr]].prev].next = queueItems[address_pos[_addr]].next;
        }
        //Update the next and prev node
        queueItems[address_pos[_addr]].next = queueItems[tailIdx].nodeId;
        queueItems[address_pos[_addr]].prev = queueItems.length + 1;

        //Updaate previous tail node 
        queueItems[tailIdx].prev = queueItems[address_pos[_addr]].nodeId; 

        //Update the current tail index
        tailIdx = address_pos[_addr];
    }

    function pushOut(uint256 count) public{
        //Update the queun info
        for(uint256 i=0; i<count; i++){
            queueItems[headIdx+i].isInQueue = false;
        }
        //Update the headIdx
        headIdx += count;
        queueItems[count].next = 0;
        breakingIdx = headIdx - 1;
    }

    //from Head(0) to it's current position
    function getCurrentPosition(address _addr) public view returns(uint256){
        uint256 ans = 0;
        uint256 start = headIdx;
        while(queueItems[start].addr != _addr){
            ans += 1;
            start = queueItems[start].prev;
        }
        return ans;
    }

    //For testing purpose
    function iterateQueue() public view{
        uint256 pointer = headIdx;
        while(pointer != tailIdx){
            console.log("Queue Item Address: ", queueItems[pointer].addr);
            pointer = queueItems[pointer].prev;
        }
        console.log("Queue Tail Address: ", queueItems[pointer].addr);
    }
}