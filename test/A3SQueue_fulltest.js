const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, network, upgrades, web3 } = require("hardhat");
const { HARDHAT_MEMPOOL_SUPPORTED_ORDERS } = require("hardhat/internal/constants");
const { boolean } = require("hardhat/internal/core/params/argumentTypes");


describe("A3SQueueContract", function () {
  const Web3Utils = require('web3-utils');
  const MaxQueueLength = 300;
  
  async function deployContractAndInit() {
    // Contracts are deployed using the first signer/account by default
    const [owner, account1, account2, otherAccounts] = await ethers.getSigners();
    const Queue = await ethers.getContractFactory("A3SQueue");
    const Token = await ethers.getContractFactory("A3STest20Token");
    const token = await Token.deploy();
    await token.deployed();
    console.log("Token deployed to address: " + token.address);

    const _walletHelper = await ethers.getContractFactory("A3SWalletHelper");
    const  WalletHelper = await _walletHelper.deploy();
    await WalletHelper.deployed();

    console.log("A3S WalletHelper has been deployed to: ", WalletHelper.address);

    const A3SWalletFactory = await ethers.getContractFactory(
        "A3SWalletFactoryV3",
        {
          libraries: { A3SWalletHelper: WalletHelper.address },
        }
    );

    const factory = await upgrades.deployProxy(A3SWalletFactory, {
        unsafeAllow: ["external-library-linking"],
    });

    await factory.deployed();
    console.log("A3SWalletFactoryProxy Address: ", factory.address);

    const currentBlock = await ethers.provider.getBlockNumber();
    const currentTimestamp = (await ethers.provider.getBlock(currentBlock)).timestamp;
    
    const queue = await Queue.deploy(token.address, owner.address, factory.address, currentTimestamp, MaxQueueLength);
    await queue.deployed();
    console.log("Queue deployed to address: " + queue.address);

    await token.approve(queue.address, BigInt(10**24));
    console.log("Approved for token to queue contract");

    //PushIn Initial 100 A3S Address:
    return { queue, token, factory, owner, account1 };
  }

  async function PushIn(Count, queue, token, factory, owner, PushedAddress){
    for(var i = 0; i<Count; i++){
      const _salt = Web3Utils.randomHex(32)
      const Addr = await factory.mintWallet(owner.address, _salt, false, 0, Web3Utils.randomHex(2))
      const mintedAddr = await factory.predictWalletAddress(owner.address, _salt)
      const tokenID = await factory.walletIdOf(mintedAddr);
      
      await queue.pushIn(mintedAddr);
      PushedAddress.push(mintedAddr);
    }
    return PushedAddress;
  }

  async function ExtendedPushIn(queue, factory, owner, PushedAddress, totalPushCount, pushingStartsIdx, maxQueueLength){
    _initialHead = await queue.headIdx();
    let startPush = false;
    for(var i = 0; i<totalPushCount-1; i++){
      const _salt = Web3Utils.randomHex(32)
      const Addr = await factory.mintWallet(owner.address, _salt, false, 0, Web3Utils.randomHex(2))
      const mintedAddr = await factory.predictWalletAddress(owner.address, _salt)
      const tokenID = await factory.walletIdOf(mintedAddr);
      await queue.pushIn(mintedAddr);
      PushedAddress.push(mintedAddr);
      if(_initialHead != await queue.headIdx()){
        startPush = true;
        expect(i).is.equal(pushingStartsIdx);
        console.log("HeadIdx changed at i= " + i);
      }
      if(startPush){
        _curHead = await queue.headIdx();
        //next round, head will be pushed and new head is curHead.prev
        _initialHead = (await queue.addressNode(_curHead)).prev;
      }
    }
    expect(await queue.curQueueLength()).is.equal(maxQueueLength);
    expect(await queue.maxQueueLength()).is.equal(maxQueueLength);
  }

  describe("A3SQueue Contract Function Tests", function () {
      it("Push In", async function (){
        //Mint and Push 200 A3S Addresses 
        const { queue, token, factory, owner } = await loadFixture(deployContractAndInit);
        const PushedAddress = await PushIn(200, queue, token, factory, owner, []);
        
        expect(PushedAddress[0]).is.equal(await queue.headIdx());
        expect(PushedAddress[PushedAddress.length - 1]).is.equal(await queue.tailIdx());
      });

      it("Jump to Tail", async function (){
        //Mint and Push 200 A3S Addresses 
        const { queue, token, factory, owner } = await loadFixture(deployContractAndInit);
        const PushedAddress = await PushIn(200, queue, token, factory, owner, []);
        //NO pushed out
        //Head Jump
        const _head = await queue.headIdx();
        await queue.jumpToTail(_head);
        console.log("Head Node with Address: " + _head + " has jumped to tail")
        expect(_head).is.equal(await queue.tailIdx());

        //Randomly jump 5 times
        var currentQueueLength = await queue.curQueueLength();
        console.log("currentQueueLength: " + currentQueueLength);
        console.log("PushedAddress length is: " + PushedAddress.length)
        for(var i=0; i<5;i++){
          var _pos = Math.floor(Math.random() * (PushedAddress.length -1));
          console.log("Jumping Address is: " + PushedAddress[_pos]);
          await queue.jumpToTail(PushedAddress[_pos]);
          console.log("Node: " + _pos + " with Address: " + PushedAddress[_pos] + " has jumped to tail")
          tailidx = await queue.tailIdx();
          expect(PushedAddress[_pos] ).is.equal(tailidx);
        }
      });

      it("Push Out", async function (){
        const { queue, token, factory, owner } = await loadFixture(deployContractAndInit);
        //First day push in 100 address
        let PushedAddress = await PushIn(100, queue, token, factory, owner, []);
        //Next day push in 200 address
        await time.increase(3600 * 24 * 1);
        PushedAddress  = await PushIn(200, queue, token, factory, owner, PushedAddress);
        //Next day push in 20 address
        //Since pre day inqueue count reaches 200, the max queue length is 318, 2 address should be pushed out 
        await time.increase(3600 * 24 * 1);
        PushedAddress = await PushIn(20, queue, token, factory, owner, PushedAddress);

        //Get the 2 pushed address
        var _globalHead = await queue.headIdx();
        var _globalHeadNode = await queue.addressNode(_globalHead);
        while(_globalHeadNode.next != ethers.constants.AddressZero){
          //_globalHead = await queue.addressNode(_globalHeadNode.next);
          _globalHeadNode = await queue.addressNode(_globalHeadNode.next);
        }
        _globalHead = _globalHeadNode.addr;
        var _global_prev = _globalHeadNode.prev;

        //Check the first 2 address correctness
        expect(_globalHead).is.equal(PushedAddress[0]);
        expect(_global_prev).is.equal(PushedAddress[1]);
        //2 pushed out nodes status is PENDING (1)
        expect((await queue.addressNode(_globalHead)).stat).is.equal(1);
        expect((await queue.addressNode(_global_prev)).stat).is.equal(1);
      });

      it("Mint", async function (){
        const { queue, token, factory, owner } = await loadFixture(deployContractAndInit);
        //First day push in 100 address
        let PushedAddress = await PushIn(100, queue, token, factory, owner, []);
        //Next day push in 200 address
        await time.increase(3600 * 24 * 1);
        PushedAddress  = await PushIn(200, queue, token, factory, owner, PushedAddress);
        //Next day push in 20 address
        //Since pre day inqueue count reaches 200, the max queue length is 318, 2 address should be pushed out 
        await time.increase(3600 * 24 * 1);
        PushedAddress = await PushIn(20, queue, token, factory, owner, PushedAddress);
        
        //Get the 2 pushed address
        var _globalHead = await queue.headIdx();
        var _globalHeadNode = await queue.addressNode(_globalHead);
        while(_globalHeadNode.next != ethers.constants.AddressZero){
          //_globalHead = await queue.addressNode(_globalHeadNode.next);
          _globalHeadNode = await queue.addressNode(_globalHeadNode.next);
        }
        _globalHead = _globalHeadNode.addr;
        var _global_prev = _globalHeadNode.prev;

        //Within 3 days Mint the first Amount:
        _balance = (await queue.addressNode(_globalHead)).balance;
        console.log("Balance of Address: " + _globalHead + " is: " + _balance);
        await queue.mint(_globalHead);
        expect(await token.balanceOf(_globalHead)).is.equal(_balance);
        expect((await queue.addressNode(_globalHead)).stat).is.equal(2);

        await expect(queue.mint(_globalHead)).to.be.revertedWith("A3S: ONLY pending status could be claimed");

        //After 3 days Mint should fail:
        await time.increase(3600 * 24 * 3);
        await expect(queue.mint(_global_prev)).to.be.revertedWith("A3S: NOT valid to calim - out of queue exceed unlocking period");
      });

      it("Jump and Steal", async function (){
        const { queue, token, factory, owner } = await loadFixture(deployContractAndInit);
        //First day push in 100 address
        let PushedAddress = await PushIn(100, queue, token, factory, owner, []);
        //Next day push in 200 address
        await time.increase(3600 * 24 * 1);
        PushedAddress  = await PushIn(200, queue, token, factory, owner, PushedAddress);
        //Next day push in 20 address
        //Since pre day inqueue count reaches 200, the max queue length is 318, 2 address should be pushed out 
        await time.increase(3600 * 24 * 1);
        PushedAddress = await PushIn(20, queue, token, factory, owner, PushedAddress);

        //Get the 2 pushed address
        var _globalHead = await queue.headIdx();
        var _globalHeadNode = await queue.addressNode(_globalHead);
        while(_globalHeadNode.next != ethers.constants.AddressZero){
          //_globalHead = await queue.addressNode(_globalHeadNode.next);
          _globalHeadNode = await queue.addressNode(_globalHeadNode.next);
        }
        _globalHead = _globalHeadNode.addr;
        var _global_prev = _globalHeadNode.prev;

        //After 3 days new head jump to steal
        await time.increase(3600 * 24 * 3);
        var _newHead = await queue.headIdx();
        var _stolenBalance = (await queue.addressNode(_globalHead)).balance;
        console.log("Stolen Balance: " + _stolenBalance);
        await queue.jumpToSteal(_newHead, _globalHead);
        expect(await token.balanceOf(_newHead)).is.equal(_stolenBalance);

        //Randomly select an address from queue, and jump steal the _global_prev balance
        var _new_stealing_pos = Math.floor(Math.random() * (await queue.curQueueLength() -1));
        var _new_staaling_addr = PushedAddress[_new_stealing_pos];
        var _stolenBalance_new = (await queue.addressNode(_global_prev)).balance;
        console.log("Stolen Balance: " + _stolenBalance_new);
        await queue.jumpToSteal(_new_staaling_addr, _global_prev);
        expect(await token.balanceOf(_new_staaling_addr)).is.equal(_stolenBalance_new);
      });

      it("Transfer Ownership", async function(){
        const { queue, token, factory, owner, account1 } = await deployContractAndInit();
        await queue.transferOwnership(account1.address);
      });

      it("Update Locking Day ", async function(){
        const { queue, token, factory, owner, account1 } = await deployContractAndInit();
        expect(await queue.lockingDay()).is.equal(3);
        await queue.updateLockingDays(5);
        expect(await queue.lockingDay()).is.equal(5);
      });

      it("Update Maximum Queue Length ", async function(){
        const { queue, token, factory, owner, account1 } = await deployContractAndInit();
        expect(await queue.maxQueueLength()).is.equal(300);
        await queue.updateMaxQueueLength(500);
        expect(await queue.maxQueueLength()).is.equal(500);
      });

      // it("Extend Queue Max Length", async function(){
      //   const { queue, token, factory, owner, PushedAddress} = await PushIn(200);
      //   //Next day 
      //   await time.increase(3600 * 24 * 1);
      //   //Continue pushing 330 nodes, reaching 300 level
      //   //max length is 218
      //   await ExtendedPushIn(queue, factory, owner, PushedAddress, 330, 18, 218);
      //   //Next day 
      //   await time.increase(3600 * 24 * 1);
      //   //Continue pushing 440 nodes, reaching 400 level
      //   //max length is 250
      //   await ExtendedPushIn(queue, factory, owner, PushedAddress, 440, 32, 250);
      //   //Next day 
      //   await time.increase(3600 * 24 * 1);
      //   //Continue pushing 550 nodes, reaching 400 level
      //   //max length is 250
      //   await ExtendedPushIn(queue, factory, owner, PushedAddress, 550, 42, 292);
      //   //Next day 
      //   await time.increase(3600 * 24 * 1);
      //   //Continue pushing 550 nodes, reaching 400 level
      //   //max length is 250
      //   await ExtendedPushIn(queue, factory, owner, PushedAddress, 620, 50, 342);
        
      // });

      

  });


});
