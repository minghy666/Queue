const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");

describe("queue", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployQueueContract() {

    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccounts] = await ethers.getSigners();

    const Queue = await ethers.getContractFactory("queue");
    const queue = await Queue.deploy();

    return { queue, owner, otherAccounts };
  }


  describe("Function call tests", function () {
    describe("call pushToQueue function", async function () {
      it("pushing 10 address to queue", async function () {
        const { queue, owner, otherAccounts } = await loadFixture(deployQueueContract);
        const _address = [];
        for(var i=0; i<10; i++){
          var _wallet = ethers.Wallet.createRandom();
          _address.push(_wallet);
          await queue.pushToQueue(_wallet.address, 600000000)
          console.log("Address: " + _wallet.address + " was pushed");
        }
        
        await queue.jumpToTail(_address[0].address);
        console.log("Node 1 with Address: " + _address[0].address + " has jumped to tail")

        await queue.iterateQueue();

        let pos = await queue.getCurrentPosition(_address[0].address);
        console.log("Node 1 current position is: " + pos);

        await queue.jumpToTail(_address[3].address);
        console.log("Node 4 with Address: " + _address[3].address + " has jumped to tail")

        await queue.iterateQueue();

        let pos1 = await queue.getCurrentPosition(_address[3].address);
        console.log("Node 4 current position is: " + pos1);
        
        await queue.jumpToTail(_address[6].address);
        console.log("Node 7 with Address: " + _address[6].address + " has jumped to tail")

        await queue.iterateQueue();

        let pos2 = await queue.getCurrentPosition(_address[6].address);
        console.log("Node 7 current position is: " + pos2);

      });


    });
  });

});
