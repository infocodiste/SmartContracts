// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy

  const NLMBO = await hre.ethers.getContractFactory("NowLambo");
  // const NowLambo = await NLMBO.deploy('0xD99D1c33F9fC3444f8101754aBC46c52416550D1', '0xd01aE4320d60Af396B307f9864Ab3ba37d396239', { gasLimit : 25000000 });
  const NowLambo = await NLMBO.deploy('0x597008Ec7854eC4B6A31DB232A0F3a4ce0B75E55', '0xd01aE4320d60Af396B307f9864Ab3ba37d396239');
  // const NowLambo = await NLMBO.deploy('0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', '0xd01aE4320d60Af396B307f9864Ab3ba37d396239');
  await NowLambo.deployed();

  console.log("NowLambo deployed to:", NowLambo.address);

  sleep(10000);
  if (network.name == "maticTestnet") {
    await hre.run("verify:verify", {
        contract: "contracts/NowLambo.sol:NowLambo",
        address: NowLambo.address,
        constructorArguments: [
            '0x597008Ec7854eC4B6A31DB232A0F3a4ce0B75E55',
            '0xd01aE4320d60Af396B307f9864Ab3ba37d396239'
        ],
    })
  }

}

function sleep(milliseconds) {
  const date = Date.now();
  let currentDate = null;
  do {
      currentDate = Date.now();
  } while (currentDate - date < milliseconds);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
