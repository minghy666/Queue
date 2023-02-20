const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");

describe("AlgoTest", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployAlgoContract() {

    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccounts] = await ethers.getSigners();

    const Algo = await ethers.getContractFactory("algo");
    const algo = await Algo.deploy();
    await algo.deployed();

    return { algo, owner, otherAccounts };
  }


  describe("Function call tests", function () {
    describe("call dijkstras function", async function () {
      it("Test", async function () {
        const { algo, owner, otherAccounts } = await loadFixture(deployAlgoContract);
        const graph = [ [ 0, 4, 0, 0, 0, 0, 0, 8, 0 ],
        [ 4, 0, 8, 0, 0, 0, 0, 11, 0 ],
        [ 0, 8, 0, 7, 0, 4, 0, 0, 2 ],
        [ 0, 0, 7, 0, 9, 14, 0, 0, 0 ],
        [ 0, 0, 0, 9, 0, 10, 0, 0, 0 ],
        [ 0, 0, 4, 14, 10, 0, 2, 0, 0 ],
        [ 0, 0, 0, 0, 0, 2, 0, 1, 6 ],
        [ 8, 11, 0, 0, 0, 0, 1, 0, 7 ],
        [ 0, 0, 2, 0, 0, 0, 6, 7, 0 ] ];

        const result = await algo.dijkstra(graph, 0);
        console.log(result);


      });


    });
  });

});
