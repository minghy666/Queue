const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { HARDHAT_MEMPOOL_SUPPORTED_ORDERS } = require("hardhat/internal/constants");


describe("A3SQueueContract", function () {
  const initialPush = 94;
  const _addressInit = [];
  const pushinTest_Count = 5;
  const _address_pushinTest = [];
  const pushoutTest_count = 10;
  const _address_pushoutTest = [];
  const jumpedTime = 8;
  const pushedTime = 8;
  for(var i=0; i<initialPush; i++){
    var _wallet = ethers.Wallet.createRandom();
    _addressInit.push(_wallet.address);
  }
  for(var i=0; i<pushinTest_Count; i++){
    var _wallet = ethers.Wallet.createRandom();
    _address_pushinTest.push(_wallet.address);
  }
  for(var i=0; i<pushoutTest_count; i++){
    var _wallet = ethers.Wallet.createRandom();
    _address_pushoutTest.push(_wallet.address);
  }
  
  async function deployContractAndInit() {
    // Contracts are deployed using the first signer/account by default
    const [owner, account1, account2, otherAccounts] = await ethers.getSigners();
    const Queue = await ethers.getContractFactory("A3SQueue");
    //const tokenAddr = ethers.utils.getAddress("0x7Cd5393ae347c6fF61EA32331247BC3BFC0DA108");
    //const valutAddr = ethers.utils.getAddress("0x22eE4D18eBC43fF8A254336d225392444D526031");
    const Token = await ethers.getContractFactory("A3STest20Token");
    const token = await Token.deploy();
    await token.deployed();
    console.log("Token deployed to address: " + token.address);
    
    const queue = await Queue.deploy(token.address, owner.address);
    await queue.deployed();
    console.log("Queue deployed to address: " + queue.address);

    await token.approve(queue.address, BigInt(10**24));
    console.log("Approved for token to queue contract");

    //Initialize queue with _address
    //const currentBlock = await ethers.provider.getBlockNumber();
    //const currentTimestamp = (await ethers.provider.getBlock(currentBlock)).timestamp;
    for(var i=0; i<initialPush; i++){
      //var _mintedTime = currentTimestamp;
      await time.increase(3600 * 24);
      await queue.pushIn(_addressInit[i])
      console.log("Address: " + _addressInit[i] + " was pushed");
    }
    return { queue, token, owner };
  }


  describe("A3SQueue Contract Function Tests", function () {
      it("Push In", async function (){
        const { queue, token, owner } = await loadFixture(deployContractAndInit);
        
        for(var i=0; i<pushinTest_Count; i++){
          await queue.pushIn(_address_pushinTest[i])
          console.log("Address: " + _address_pushinTest[i]+ " was pushed");
        }
        headidx = await queue.getHead();
        tailidx = await queue.getTail()
        expect(_addressInit[0]).is.equal(headidx);
        expect(_address_pushinTest[pushinTest_Count - 1]).is.equal(tailidx);

        await queue.iterateQueue();

      });

      it("Jump to Tail", async function (){
        const { queue, token, owner } = await loadFixture(deployContractAndInit);

        await queue.jumpToTail(_addressInit[0]);
        console.log("Node: 0 with Address: " + _addressInit[0] + " has jumped to tail")
        headidx = await queue.getHead();
        tailidx = await queue.getTail();
        expect(_addressInit[1]).is.equal(headidx);
        expect(_addressInit[0]).is.equal(tailidx);
        for(var i=0; i<jumpedTime;i++){
          var _pos = Math.floor(Math.random() * initialPush);
          await queue.jumpToTail(_addressInit[_pos]);
          console.log("Node: " + _pos + " with Address: " + _addressInit[_pos] + " has jumped to tail")
          tailidx = await queue.getTail();
          expect(_addressInit[_pos]).is.equal(tailidx);
        }
        await queue.iterateQueue();
      });

      it("Push Out", async function (){
        const { queue, token, owner } = await loadFixture(deployContractAndInit);

        for (var i = 0; i< pushedTime; i++){
          _curNode = await queue.getHead()
          console.log("Start Pushing out the nodes: " + _curNode);
          await queue.pushOut();
          headIdx = await queue.getHead()
          _stat = await queue.getStat(_curNode)
          expect(headIdx).is.equal(_addressInit[i+1]);
          expect(_stat).is.equal(1);
        }
        await queue.iterateQueue();
      });

      it("Mint", async function (){
        const { queue, token, owner } = await loadFixture(deployContractAndInit);

        console.log("------------- Before Push ---------------")
        await queue.iterateQueue();
        console.log("------------- Start Push ---------------")
        for(var i=0; i<pushoutTest_count; i++){
          
          await queue.pushIn(_address_pushoutTest[i])
          console.log("Address: " + _address_pushoutTest[i]+ " was pushed in");
        }
        console.log("------------- After Push ---------------")
        await queue.iterateQueue();
        const GLBHEAD = await queue.getGloabalHead()
        var _globalHead = GLBHEAD;
        
        console.log("Global Head: " + _globalHead);
        for(var i=0; i<4; i++){
          expect(_addressInit[i]).is.equal(_globalHead);
          _globalHead = await queue.getPrev(_globalHead);
        }
        await queue.mint(GLBHEAD);
        console.log("claim successed for address: " + GLBHEAD);
        
        await expect(queue.mint(GLBHEAD)).to.be.revertedWith("A3S: ONLY pending status could be claimed");
        await time.increase(3600 * 24 * 4);
        //await queue.claim(GLBHEAD);
        await expect(queue.mint(_addressInit[3])).to.be.revertedWith("A3S: NOT valid to calim - out of queue exceed 3 days");

      });

      it("Jump and Steal", async function (){
        const { queue, token, owner } = await loadFixture(deployContractAndInit);

        console.log("------------- Before Push ---------------")
        await queue.iterateQueue();
        console.log("------------- Start Push ---------------")
        for(var i=0; i<pushoutTest_count; i++){
          
          await queue.pushIn(_address_pushoutTest[i])
          console.log("Address: " + _address_pushoutTest[i]+ " was pushed in");
        }
        console.log("------------- After Push ---------------")
        await queue.iterateQueue();
        
        var _head = await queue.getHead();
        console.log("------------- Within 3 days Call ---------------")
        for(var i=0; i<4; i++){
          await expect(queue.jumpToSteal(_head, _addressInit[i])).to.be.revertedWith("A3S: NOT valid to steal - not reaching 3 days");
        }

        await time.increase(3600 * 24 * 3);
        console.log("------------- After 3 days Call ---------------")
        for(var i=0; i<4; i++){
          const currentBlock = await ethers.provider.getBlockNumber();
          const currentTimestamp = (await ethers.provider.getBlock(currentBlock)).timestamp;
          console.log("Current time: " + currentTimestamp);
          console.log("Stolen Address: " + _addressInit[i]);
          await queue.jumpToSteal(_head, _addressInit[i]);
          expect(await queue.getStat(_addressInit[i])).is.equal(3);
          _head = await queue.getHead();
        }

      });

      // it("Calculate maxLengh Extended param", async function(){
      //   const { queue, token, owner } = await loadFixture(deployContractAndInit);
        
      //   for (var i =1; i<= 21; i++){
      //     var pra = await queue._getExtendLength(i * 100);
      //     console.log(pra);
      //   }

      // });

      // it("Push In Exceed Maximum and Start Pushing out", async function (){
      //   const { queue, token, owner } = await loadFixture(deployContractAndInit);
      //   console.log("------------- Before Push ---------------")
      //   await queue.iterateQueue();
      //   console.log("------------- Start Push ---------------")
      //   for(var i=0; i<pushoutTest_count; i++){
          
      //     await queue.pushIn(_address_pushoutTest[i])
      //     console.log("Address: " + _address_pushoutTest[i]+ " was pushed ");
      //   }
      //   console.log("------------- After Push ---------------")
      //   await queue.iterateQueue();

      //   console.log("------------- More Push: 200 to 2100 ---------------");
      //   for(var j=2; j<=5; j++){
      //     console.log("------------- More Push: " + j*101 + "---------------");
      //     await time.increase(3600 * 24);
      //     for(var i=0; i<j*101; i++){
      //       var _wallet = ethers.Wallet.createRandom();
      //       await queue.pushIn(_wallet.address);
      //     }
      //     done();
      //   }

      // });

      


  });


});
