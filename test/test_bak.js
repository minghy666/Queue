const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, network } = require("hardhat");


describe("A3STokenContract", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployQueueContract() {

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

    return { queue, token, owner, otherAccounts };

  }


  describe("Function call tests", function () {
    describe("Testing Start", async function () {
      it("Queue Logic: pushIn, pushOut, jumpToTail", async function () {
        const { queue, token, owner, otherAccounts } = await loadFixture(deployQueueContract);
        //get block timestamp
        const currentBlock = await ethers.provider.getBlockNumber();
        const currentTimestamp = (await ethers.provider.getBlock(currentBlock)).timestamp;
        console.log("Timestamp: ", currentTimestamp);

        const totalPush = 20;
        const jumpedTime = 3;
        const pushedCount = 3;
        const pushedTime = 3;
        const _address = [];

        for(var i=0; i<totalPush; i++){
          var _wallet = ethers.Wallet.createRandom();
          _address.push(_wallet.address);
          var _mintedTime = currentTimestamp - 86400 * (totalPush - i+1);
          await queue.pushIn(_wallet.address, _mintedTime)
          console.log("Address: " + _wallet.address + " was pushed with In-Queue time of: ", + _mintedTime);
        }

        await queue.iterateQueue();
        console.log("--------------------------------- PushIn Test Completed ---------------------------------")

        await queue.jumpToTail(_address[0]);
        console.log("Node: 0 with Address: " + _address[0] + " has jumped to tail")
        for(var i=0; i<jumpedTime;i++){
          var _pos = Math.floor(Math.random() * totalPush);
          await queue.jumpToTail(_address[_pos]);
          console.log("Node: " + _pos + " with Address: " + _address[_pos] + " has jumped to tail")
        }

        await queue.iterateQueue();
        console.log("--------------------------------- JumpToTail test Completed ---------------------------------")


        for (var i = 0; i< pushedTime; i++){
          _head = await queue.getHead()
          console.log("Start Pushing out nodes: " + _head);
          await queue.pushOut();
        }

        await queue.iterateQueue();
        console.log("--------------------------------- PushOut test Completed ---------------------------------")

        const globalHead = await queue.getGloabalHead();
        console.log("Global Head Address: " + globalHead);
        let currAddr = globalHead;

        let _currentBlock = await ethers.provider.getBlockNumber();
        let _currentTimestamp = (await ethers.provider.getBlock(currentBlock)).timestamp;
        console.log("Current Time: " + _currentTimestamp);
        await queue.claim(currAddr);
        console.log("Claim completed");
        // for (var i=0; i<pushedTime; i++){
        //   console.log("----------BEFORE TRANSFER----------");
        //   console.log("Vault Address: " + owner.address);
        //   console.log("To Address: " + currAddr);
        //   console.log("Balance of Vault: " + await token.balanceOf(owner.address));
        //   console.log("Balance of to: " + await token.balanceOf(currAddr));
        //   console.log("Status: " + await queue.getStat(currAddr));

        //   await queue.claim(currAddr);
          
        //   console.log("----------After TRANSFER----------");
        //   console.log("Vault Address: " + owner.address);
        //   console.log("To Address: " + currAddr);
        //   console.log("Balance of Vault: " + await token.balanceOf(owner.address));
        //   console.log("Balance of to: " + await token.balanceOf(currAddr));
        //   console.log("Status: " + await queue.getStat(currAddr));

        //   currAddr = await queue.getPrev(currAddr);
        // }
        console.log("--------------------------------- Claim test Completed ---------------------------------")

        console.log("--------------------------------- Steal test Completed ---------------------------------")

      });
    });

    // describe("Prepare tokens", async function(){
    //   it("Mint token to Valut and approve for the queue contract", async function(){
    //     const tokenContractABI = require("../artifacts/contracts/token.sol/A3STest20Token.json");
    //     const alchemyProvider = new ethers.providers.AlchemyProvider("goerli", process.env.ALCHEMY_KEY);
    //     const signer = new ethers.Wallet(process.env.PRIVATE_KEY, alchemyProvider);
    //     const tokenAddr = ethers.utils.getAddress("0x7Cd5393ae347c6fF61EA32331247BC3BFC0DA108");
    //     const valutAddr = ethers.utils.getAddress("0x22eE4D18eBC43fF8A254336d225392444D526031");

    //     const tokenContract = new ethers.Contract(tokenAddr, tokenContractABI.abi, signer);
    //     await tokenContract.mint(valutAddr, BigInt(1000000000000000000000000));
    //     console.log("Mint successs to: " + valutAddr + " with amount of: " + BigInt(1000000000000000000000000));

    //     const { queue, owner, otherAccounts } = await loadFixture(deployQueueContract);
    //     await tokenContract.approve(queue.address, BigInt(1000000000000000000000000));
    //     console.log("Approve successs to: " + queue.address + " with amount of: " + BigInt(1000000000000000000000000));

    //   });
    // });
  });

});
