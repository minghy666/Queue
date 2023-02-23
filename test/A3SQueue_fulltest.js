const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, network, upgrades, web3 } = require("hardhat");
const { HARDHAT_MEMPOOL_SUPPORTED_ORDERS } = require("hardhat/internal/constants");


describe("A3SQueueContract", function () {
  const Web3Utils = require('web3-utils');
  
  
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
    
    const queue = await Queue.deploy(token.address, owner.address, factory.address, currentTimestamp);
    await queue.deployed();
    console.log("Queue deployed to address: " + queue.address);

    await token.approve(queue.address, BigInt(10**24));
    console.log("Approved for token to queue contract");

    return { queue, token, factory, owner };
  }

  async function PushIn(Count){
    var PushedAddress = []
    const { queue, token, factory, owner } = await loadFixture(deployContractAndInit);
    
    for(var i = 0; i<Count; i++){
      const _salt = Web3Utils.randomHex(32)
      const Addr = await factory.mintWallet(owner.address, _salt, false, 0, Web3Utils.randomHex(2))
      const mintedAddr = await factory.predictWalletAddress(owner.address, _salt)
      const tokenID = await factory.walletIdOf(mintedAddr);
      
      await queue.pushIn(mintedAddr);
      PushedAddress.push(mintedAddr);
    }
    return { queue, token, factory, owner, PushedAddress };
  }

  describe("A3SQueue Contract Function Tests", function () {
      it("Deploy Contracts", async function(){
        await deployContractAndInit();
      });

      it("Push In", async function (){
        //Mint and Push 200 A3S Addresses 
        const { queue, token, factory, owner, PushedAddress } = await PushIn(200)
        
        expect(PushedAddress[0]).is.equal(await queue.headIdx());
        expect(PushedAddress[PushedAddress.length - 1]).is.equal(await queue.tailIdx());
      });

      it("Jump to Tail", async function (){
        const { queue, token, factory, owner, PushedAddress } = await PushIn(200)
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
        //First day push in 200 address
        const { queue, token, factory, owner, PushedAddress} = await PushIn(200)
        //Next day push in 20 address
        //Since pre day inqueue count reaches 200, the max queue length is 218, 2 address should be pushed out 
        await time.increase(3600 * 24 * 1);
        for(var i = 0; i<20; i++){
          const _salt = Web3Utils.randomHex(32)
          const Addr = await factory.mintWallet(owner.address, _salt, false, 0, Web3Utils.randomHex(2))
          const mintedAddr = await factory.predictWalletAddress(owner.address, _salt)
          const tokenID = await factory.walletIdOf(mintedAddr);
          await queue.pushIn(mintedAddr);
          PushedAddress.push(mintedAddr);
        }

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
        //First day push in 200 address
        const { queue, token, factory, owner, PushedAddress } = await PushIn(200)
        await time.increase(3600 * 24 * 1);
        for(var i = 0; i<20; i++){
          const _salt = Web3Utils.randomHex(32)
          const Addr = await factory.mintWallet(owner.address, _salt, false, 0, Web3Utils.randomHex(2))
          const mintedAddr = await factory.predictWalletAddress(owner.address, _salt)
          const tokenID = await factory.walletIdOf(mintedAddr);
          await queue.pushIn(mintedAddr);
          PushedAddress.push(mintedAddr);
        }
        
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
        await expect(queue.mint(_global_prev)).to.be.revertedWith("A3S: NOT valid to calim - out of queue exceed 3 days");
      });

      it("Jump and Steal", async function (){
        //First day push in 200 address
        const { queue, token, factory, owner, PushedAddress} = await PushIn(200)
        //Next day push in 20 address
        //Since pre day inqueue count reaches 200, the max queue length is 218, 2 address should be pushed out 
        await time.increase(3600 * 24 * 1);
        for(var i = 0; i<20; i++){
          const _salt = Web3Utils.randomHex(32)
          const Addr = await factory.mintWallet(owner.address, _salt, false, 0, Web3Utils.randomHex(2))
          const mintedAddr = await factory.predictWalletAddress(owner.address, _salt)
          const tokenID = await factory.walletIdOf(mintedAddr);
          await queue.pushIn(mintedAddr);
          PushedAddress.push(mintedAddr);
        }

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
  });


});
