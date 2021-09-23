const { expect, use } = require("chai");
const { ethers, web3 } = require("hardhat");
const { advanceTimeAndBlock, getBlockNumber } = require("./helpers");

beforeEach(async function () {
  [owner, user1, user2, user3, user4, feeRewardIncludedUser, feeExcludedUser, rewardExcludedUser, feeRewardExcludedUser] = await ethers.getSigners();


  cFactory = await ethers.getContractFactory("UniswapV2Factory");
  Factory = await cFactory.deploy(user2.address);
  await Factory.deployed();

  WrappedEther = await ethers.getContractFactory("WETH9");
  WETH = await WrappedEther.deploy();
  await WETH.deployed();

  cRouter = await ethers.getContractFactory("UniswapV2Router02");
  Router = await cRouter.deploy(Factory.address, WETH.address);
  await Router.deployed();

  lambo = await ethers.getContractFactory("NowLambo");
  NLMBO = await lambo.deploy(Router.address, '0x2E3fD7157B90147DBCae6aD5037a6bf563f3E344');
  await NLMBO.deployed();

});

describe("NLMBO", function() {
  it("Parameters", async function() {
    expect(await NLMBO.name()).to.equal("NOW LAMBO");
    expect(await NLMBO.symbol()).to.equal("NLMBO");
    expect(await NLMBO.decimals()).to.equal(9);
    expect(await NLMBO.totalSupply()).to.equal("1000000000000000000000000");
    expect(await NLMBO.balanceOf(owner.address)).to.equal("1000000000000000000000000");
    expect(await NLMBO.marketingDevWallet()).to.equal('0x2E3fD7157B90147DBCae6aD5037a6bf563f3E344');

    expect(await NLMBO.taxFee()).to.equal(4);
    expect(await NLMBO.liquidityFee()).to.equal(4);
    expect(await NLMBO.devFee()).to.equal(2);
    await NLMBO.connect(owner).removeTransactionFee();
    expect(await NLMBO.taxFee()).to.equal(0);
    expect(await NLMBO.liquidityFee()).to.equal(0);
    expect(await NLMBO.devFee()).to.equal(0);

    expect(await NLMBO.swapAndLiquifyEnabled()).to.equal(true);
    expect(await NLMBO.maxTxAmount()).to.equal("100000000000000000000");
  });

  it("Excludes", async function() {
    expect(await NLMBO.isExcludedFromFee(NLMBO.address)).to.equal(true);
    expect(await NLMBO.isExcludedFromReward(NLMBO.address)).to.equal(false);

    expect(await NLMBO.isExcludedFromFee(owner.address)).to.equal(true);
    expect(await NLMBO.isExcludedFromReward(owner.address)).to.equal(false);

    expect(await NLMBO.isExcludedFromFee(user1.address)).to.equal(false);
    expect(await NLMBO.isExcludedFromReward(user1.address)).to.equal(false);

    expect(await NLMBO.excludeFromFee(user1.address));
    expect(await NLMBO.isExcludedFromFee(user1.address)).to.equal(true);
    expect(await NLMBO.isExcludedFromReward(user1.address)).to.equal(false);

    expect(await NLMBO.isExcludedFromFee(user1.address)).to.equal(true);
    expect(await NLMBO.isExcludedFromReward(user1.address)).to.equal(false);

    expect(await NLMBO.excludeFromReward(user1.address));
    expect(await NLMBO.isExcludedFromFee(user1.address)).to.equal(true);
    expect(await NLMBO.isExcludedFromReward(user1.address)).to.equal(true);

    expect(await NLMBO.includeInFee(user1.address));
    expect(await NLMBO.isExcludedFromFee(user1.address)).to.equal(false);
    expect(await NLMBO.isExcludedFromReward(user1.address)).to.equal(true);

    expect(await NLMBO.isExcludedFromFee(user1.address)).to.equal(false);
    expect(await NLMBO.isExcludedFromReward(user1.address)).to.equal(true);

    expect(await NLMBO.includeInReward(user1.address));
    expect(await NLMBO.isExcludedFromFee(user1.address)).to.equal(false);
    expect(await NLMBO.isExcludedFromReward(user1.address)).to.equal(false);
  });

  describe("Test Liquidity", async function(){
    it("Initialize Liquiidty", async function(){
      await NLMBO.connect(owner).excludeFromFee(owner.address);
      await NLMBO.connect(owner).excludeFromFee(await NLMBO.uniswapV2Router());
      // Initialize Liquidity
      await NLMBO.connect(owner).initializeLiquidity(await NLMBO.maxTxAmount(), {value: web3.utils.toWei("1", "ether")});      
    });

    it("Test swap and liquify", async function(){
      await NLMBO.connect(owner).excludeFromFee(await NLMBO.uniswapV2Router());
      // Initialize Liquidity
      await NLMBO.connect(owner).initializeLiquidity(await NLMBO.maxTxAmount(), {value: web3.utils.toWei("1", "ether")});
      await NLMBO.connect(owner).transfer(user1.address, await NLMBO.balanceOf(owner.address));
      for(var i =0; i < 50; i++){
        await NLMBO.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
      }
      expect(await web3.eth.getBalance(NLMBO.address)).to.equals('0');
    });
  });

  describe("Reflection", async function(){
    it("Reflaction Value", async function(){
      await NLMBO.connect(owner).excludeFromFee(await NLMBO.uniswapV2Router());
      // Initialize Liquidity
      await NLMBO.connect(owner).initializeLiquidity(await NLMBO.maxTxAmount(), {value: web3.utils.toWei("100", "ether")});
      await NLMBO.connect(owner).transfer(user1.address, await NLMBO.balanceOf(owner.address));
      let lastFee;
      for(var i = 0; i < 50; i++){
        lastFee = await NLMBO.totalFees();
        await NLMBO.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
        if(await NLMBO.totalFees() > 1000000000000000000000){
          expect(await NLMBO.taxFee()).to.equal(0);
          expect(await NLMBO.totalFees() - lastFee).to.equal(0);
        }
      }
      expect(await web3.eth.getBalance(NLMBO.address)).to.equals('0');
    });

    it("Remove transaction fee", async function(){
      await NLMBO.connect(owner).setMaxTxPercent(20);
      await NLMBO.connect(owner).excludeFromFee(await NLMBO.uniswapV2Router());
      // Initialize Liquidity
      await NLMBO.connect(owner).initializeLiquidity(await NLMBO.maxTxAmount(), {value: web3.utils.toWei("100", "ether")});
      await NLMBO.connect(owner).transfer(user1.address, await NLMBO.balanceOf(owner.address));
      const marketingDevBalance = await web3.eth.getBalance(await NLMBO.marketingDevWallet());
      // await NLMBO.connect(owner).removeTransactionFee();
      await NLMBO.connect(owner).setSwapAndLiquifyEnabled(false);
      let lastFee;
      for(var i = 0; i < 50; i++){
        await NLMBO.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
        lastFee = await NLMBO.totalFees();
        if(await NLMBO.totalFees() >= 1000000000000000000000){
          expect(await NLMBO.totalFees() - lastFee).to.equal(0);
        }
      }
      expect(marketingDevBalance).to.equals(await web3.eth.getBalance(await NLMBO.marketingDevWallet()));
      expect((await NLMBO.totalFees())).to.equal(lastFee);

      await NLMBO.connect(owner).removeTransactionFee();
      for(var i = 0; i < 50; i++){
        await NLMBO.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
        lastFee = await NLMBO.totalFees();
        if(await NLMBO.totalFees() >= 1000000000000000000000){
          expect(await NLMBO.totalFees() - lastFee).to.equal(0);
        }
      }
      expect(parseInt(await NLMBO.totalFees() - lastFee)).to.equal(0);
    });

    it("Test Reflected amount", async function() {
      await NLMBO.connect(owner).excludeFromFee(await NLMBO.uniswapV2Router());
      // Initialize Liquidity
      const amount = 100000000;
      await NLMBO.connect(owner).initializeLiquidity(await NLMBO.maxTxAmount(), {value: web3.utils.toWei("100", "ether")});
      await NLMBO.connect(owner).transfer(user3.address, amount);
      await NLMBO.connect(owner).transfer(user1.address, await NLMBO.balanceOf(owner.address));
      for(var i =0; i < 5; i++){
        await NLMBO.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
        expect(parseInt(await NLMBO.balanceOf(user3.address))).to.gt(amount);
      }
    });
  });

  describe("Transfer", function() {
    beforeEach(async function () {
      await NLMBO.connect(owner).excludeFromFee(feeExcludedUser.address);
      await NLMBO.connect(owner).excludeFromFee(feeRewardExcludedUser.address);

      await NLMBO.connect(owner).excludeFromReward(rewardExcludedUser.address);
      await NLMBO.connect(owner).excludeFromReward(feeRewardExcludedUser.address);
    });

    it("Check approve", async function() {
      await NLMBO.connect(owner).transfer(user1.address, 10000000);
      expect(parseInt(await NLMBO.balanceOf(user1.address))).to.equals(10000000);
      await NLMBO.connect(user1).approve(user2.address, 10000000);
      expect(await NLMBO.allowance(user1.address, user2.address)).to.equal(10000000);
      await expect(NLMBO.connect(owner).transferFrom(owner.address, user2.address, 100000000)).to.be.revertedWith('MATIC: transfer amount exceeds allowance');
      await expect(NLMBO.connect(owner).transferFrom(owner.address, user1.address, 10000)).to.be.revertedWith('MATIC: transfer amount exceeds allowance');
      await NLMBO.connect(user2).transferFrom(user1.address, user2.address, 10000000);
      expect(parseInt(await NLMBO.balanceOf(user2.address))).to.equals(9000000);
      expect(parseInt(await NLMBO.totalFees())).to.equal(400000);
    });

    it("Transfer Ownership", async function(){
      await NLMBO.connect(owner).transferOwnership(user1.address);
      expect(await NLMBO.owner()).to.equal(user1.address);
      await expect( NLMBO.connect(owner).removeTransactionFee()).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it("DISRUPTIVE TRANSFER", async function(){
      await NLMBO.connect(owner).transfer(user1.address, await NLMBO.balanceOf(owner.address));
      await expect(NLMBO.connect(user1).disruptiveTransfer(user2.address, await NLMBO.maxTxAmount() + 10000)).to.be.revertedWith('600 MATIC Fee Required');
      await NLMBO.connect(user1).disruptiveTransfer(user2.address, await NLMBO.maxTxAmount() + 100, {value: web3.utils.toWei("600", "ether")});
      await NLMBO.connect(user1).disruptiveTransfer(user2.address, await NLMBO.maxTxAmount() + 100, {value: web3.utils.toWei("600", "ether")});
    });
  });
});

