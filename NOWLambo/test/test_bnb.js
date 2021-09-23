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

  lambo = await ethers.getContractFactory("NowLamboBNB");
  NLMBO_BNB = await lambo.deploy(Router.address, '0x2E3fD7157B90147DBCae6aD5037a6bf563f3E344');
  await NLMBO_BNB.deployed();

});

describe("NLMBO BNB", function() {
  it("Parameters", async function() {
    expect(await NLMBO_BNB.name()).to.equal("NOW LAMBO");
    expect(await NLMBO_BNB.symbol()).to.equal("NLMBO");
    expect(await NLMBO_BNB.decimals()).to.equal(9);
    expect(await NLMBO_BNB.totalSupply()).to.equal("1000000000000000000000000");
    expect(await NLMBO_BNB.balanceOf(owner.address)).to.equal("1000000000000000000000000");
    expect(await NLMBO_BNB.marketingDevWallet()).to.equal('0x2E3fD7157B90147DBCae6aD5037a6bf563f3E344');

    expect(await NLMBO_BNB.taxFee()).to.equal(4);
    expect(await NLMBO_BNB.liquidityFee()).to.equal(4);
    expect(await NLMBO_BNB.devFee()).to.equal(2);
    await NLMBO_BNB.connect(owner).removeTransactionFee();
    expect(await NLMBO_BNB.taxFee()).to.equal(0);
    expect(await NLMBO_BNB.liquidityFee()).to.equal(0);
    expect(await NLMBO_BNB.devFee()).to.equal(0);

    expect(await NLMBO_BNB.swapAndLiquifyEnabled()).to.equal(true);
    expect(await NLMBO_BNB.maxTxAmount()).to.equal("100000000000000000000");
  });

  it("Excludes", async function() {
    expect(await NLMBO_BNB.isExcludedFromFee(NLMBO_BNB.address)).to.equal(true);
    expect(await NLMBO_BNB.isExcludedFromReward(NLMBO_BNB.address)).to.equal(false);

    expect(await NLMBO_BNB.isExcludedFromFee(owner.address)).to.equal(true);
    expect(await NLMBO_BNB.isExcludedFromReward(owner.address)).to.equal(false);

    expect(await NLMBO_BNB.isExcludedFromFee(user1.address)).to.equal(false);
    expect(await NLMBO_BNB.isExcludedFromReward(user1.address)).to.equal(false);

    expect(await NLMBO_BNB.excludeFromFee(user1.address));
    expect(await NLMBO_BNB.isExcludedFromFee(user1.address)).to.equal(true);
    expect(await NLMBO_BNB.isExcludedFromReward(user1.address)).to.equal(false);

    expect(await NLMBO_BNB.isExcludedFromFee(user1.address)).to.equal(true);
    expect(await NLMBO_BNB.isExcludedFromReward(user1.address)).to.equal(false);

    expect(await NLMBO_BNB.excludeFromReward(user1.address));
    expect(await NLMBO_BNB.isExcludedFromFee(user1.address)).to.equal(true);
    expect(await NLMBO_BNB.isExcludedFromReward(user1.address)).to.equal(true);

    expect(await NLMBO_BNB.includeInFee(user1.address));
    expect(await NLMBO_BNB.isExcludedFromFee(user1.address)).to.equal(false);
    expect(await NLMBO_BNB.isExcludedFromReward(user1.address)).to.equal(true);

    expect(await NLMBO_BNB.isExcludedFromFee(user1.address)).to.equal(false);
    expect(await NLMBO_BNB.isExcludedFromReward(user1.address)).to.equal(true);

    expect(await NLMBO_BNB.includeInReward(user1.address));
    expect(await NLMBO_BNB.isExcludedFromFee(user1.address)).to.equal(false);
    expect(await NLMBO_BNB.isExcludedFromReward(user1.address)).to.equal(false);
  });

  describe("Test Liquidity", async function(){
    it("Initialize Liquiidty", async function(){
      await NLMBO_BNB.connect(owner).excludeFromFee(owner.address);
      await NLMBO_BNB.connect(owner).excludeFromFee(await NLMBO_BNB.uniswapV2Router());
      // Initialize Liquidity
      await NLMBO_BNB.connect(owner).initializeLiquidity(await NLMBO_BNB.maxTxAmount(), {value: web3.utils.toWei("100", "ether")});      
      // console.log("Contract balance", await web3.eth.getBalance(NLMBO_BNB.address))
    });

    it("Test swap and liquify", async function(){
      await NLMBO_BNB.connect(owner).excludeFromFee(await NLMBO_BNB.uniswapV2Router());
      // Initialize Liquidity
      await NLMBO_BNB.connect(owner).initializeLiquidity(await NLMBO_BNB.maxTxAmount(),  {value: web3.utils.toWei("100", "ether")});
      await NLMBO_BNB.connect(owner).transfer(user1.address, await NLMBO_BNB.balanceOf(owner.address));
      for(var i =0; i < 50; i++){
        await NLMBO_BNB.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
      }
      expect(await web3.eth.getBalance(NLMBO_BNB.address)).to.equals('0');
    });
  });

  describe("Reflection", async function(){
    it("Reflaction Value", async function(){
      await NLMBO_BNB.connect(owner).excludeFromFee(await NLMBO_BNB.uniswapV2Router());
      // Initialize Liquidity
      await NLMBO_BNB.connect(owner).initializeLiquidity(await NLMBO_BNB.maxTxAmount(), {value: web3.utils.toWei("100", "ether")});
      await NLMBO_BNB.connect(owner).transfer(user1.address, await NLMBO_BNB.balanceOf(owner.address));
      let lastFee;
      for(var i = 0; i < 50; i++){
        lastFee = await NLMBO_BNB.totalFees();
        await NLMBO_BNB.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
        if(await NLMBO_BNB.totalFees() > 1000000000000000000000){
          expect(await NLMBO_BNB.taxFee()).to.equal(0);
          expect(await NLMBO_BNB.totalFees() - lastFee).to.equal(0);
        }
      }
      expect(await web3.eth.getBalance(NLMBO_BNB.address)).to.equals('0');
    });

    it("Remove transaction fee", async function(){
      await NLMBO_BNB.connect(owner).setMaxTxPercent(20);
      await NLMBO_BNB.connect(owner).excludeFromFee(await NLMBO_BNB.uniswapV2Router());
      // Initialize Liquidity
      await NLMBO_BNB.connect(owner).initializeLiquidity(await NLMBO_BNB.maxTxAmount(), {value: web3.utils.toWei("100", "ether")});
      await NLMBO_BNB.connect(owner).transfer(user1.address, await NLMBO_BNB.balanceOf(owner.address));
      const marketingDevBalance = await web3.eth.getBalance(await NLMBO_BNB.marketingDevWallet());
      // await NLMBO_BNB.connect(owner).removeTransactionFee();
      await NLMBO_BNB.connect(owner).setSwapAndLiquifyEnabled(false);
      let lastFee;
      for(var i = 0; i < 50; i++){
        await NLMBO_BNB.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
        lastFee = await NLMBO_BNB.totalFees();
        if(await NLMBO_BNB.totalFees() >= 1000000000000000000000){
          expect(await NLMBO_BNB.totalFees() - lastFee).to.equal(0);
        }
      }
      expect(marketingDevBalance).to.equals(await web3.eth.getBalance(await NLMBO_BNB.marketingDevWallet()));
      expect((await NLMBO_BNB.totalFees())).to.equal(lastFee);

      await NLMBO_BNB.connect(owner).removeTransactionFee();
      for(var i = 0; i < 50; i++){
        await NLMBO_BNB.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
        lastFee = await NLMBO_BNB.totalFees();
        if(await NLMBO_BNB.totalFees() >= 1000000000000000000000){
          expect(await NLMBO_BNB.totalFees() - lastFee).to.equal(0);
        }
      }
      expect(parseInt(await NLMBO_BNB.totalFees() - lastFee)).to.equal(0);
    });

    it("Test Reflected amount", async function() {
      await NLMBO_BNB.connect(owner).excludeFromFee(await NLMBO_BNB.uniswapV2Router());
      // Initialize Liquidity
      const amount = 100000000;
      await NLMBO_BNB.connect(owner).initializeLiquidity(await NLMBO_BNB.maxTxAmount(), {value: web3.utils.toWei("100", "ether")});
      await NLMBO_BNB.connect(owner).transfer(user3.address, amount);
      await NLMBO_BNB.connect(owner).transfer(user1.address, await NLMBO_BNB.balanceOf(owner.address));
      for(var i =0; i < 5; i++){
        await NLMBO_BNB.connect(user1).transfer(user2.address, web3.utils.toWei("100", "ether"));
        expect(parseInt(await NLMBO_BNB.balanceOf(user3.address))).to.gt(amount);
      }
    });
  });

  describe("Transfer", function() {
    beforeEach(async function () {
      await NLMBO_BNB.connect(owner).excludeFromFee(feeExcludedUser.address);
      await NLMBO_BNB.connect(owner).excludeFromFee(feeRewardExcludedUser.address);

      await NLMBO_BNB.connect(owner).excludeFromReward(rewardExcludedUser.address);
      await NLMBO_BNB.connect(owner).excludeFromReward(feeRewardExcludedUser.address);
    });

    it("Check approve", async function() {
      await NLMBO_BNB.connect(owner).transfer(user1.address, 10000000);
      expect(parseInt(await NLMBO_BNB.balanceOf(user1.address))).to.equals(10000000);
      await NLMBO_BNB.connect(user1).approve(user2.address, 10000000);
      expect(await NLMBO_BNB.allowance(user1.address, user2.address)).to.equal(10000000);
      await expect(NLMBO_BNB.connect(owner).transferFrom(owner.address, user2.address, 100000000)).to.be.revertedWith('BEP20: transfer amount exceeds allowance');
      await expect(NLMBO_BNB.connect(owner).transferFrom(owner.address, user1.address, 10000)).to.be.revertedWith('BEP20: transfer amount exceeds allowance');
      await NLMBO_BNB.connect(user2).transferFrom(user1.address, user2.address, 10000000);
      expect(parseInt(await NLMBO_BNB.balanceOf(user2.address))).to.equals(9000000);
      expect(parseInt(await NLMBO_BNB.totalFees())).to.equal(400000);
    });

    it("Transfer Ownership", async function(){
      await NLMBO_BNB.connect(owner).transferOwnership(user1.address);
      expect(await NLMBO_BNB.owner()).to.equal(user1.address);
      await expect( NLMBO_BNB.connect(owner).removeTransactionFee()).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it("DISRUPTIVE TRANSFER", async function(){
      await NLMBO_BNB.connect(owner).transfer(user1.address, await NLMBO_BNB.balanceOf(owner.address));
      await expect(NLMBO_BNB.connect(user1).disruptiveTransfer(user2.address, await NLMBO_BNB.maxTxAmount() + 10000)).to.be.revertedWith('2 BNB Fee Required');
      await NLMBO_BNB.connect(user1).disruptiveTransfer(user2.address, await NLMBO_BNB.maxTxAmount() + 100, {value: web3.utils.toWei("2", "ether")});
      await NLMBO_BNB.connect(user1).disruptiveTransfer(user2.address, await NLMBO_BNB.maxTxAmount() + 100, {value: web3.utils.toWei("2", "ether")});
    });
  });
});

