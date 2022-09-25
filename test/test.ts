/* eslint-disable @typescript-eslint/no-inferrable-types */
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable prettier/prettier */
// eslint-disable-next-line prettier/prettier
import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { expect } from "chai";

dotenv.config();

const ETH_NODE_URL: string = `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`;
let Wrapper : any;
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
const LendingPoolAddress = "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9"

describe("Aave Wrapper", function () {

    let account1: SignerWithAddress;

    beforeEach(async function () {
        await ethers.provider.send(
            "hardhat_reset",
            [
                {
                    forking: {
                        jsonRpcUrl: ETH_NODE_URL,
                        // blockNumber: 15611047
                    },
                },
            ],
        );

        const accounts = await ethers.getSigners()

        account1 = accounts[0]
        console.log("=================1================", account1.address)
        // Here we get the factory for our Swapper contrat and we deploy it on the forked network
        const WrapperFactory = await ethers.getContractFactory("AaveWrapper")
        Wrapper = await WrapperFactory.deploy();
        console.log("Contract Address",Wrapper.address);
    });

    it("Aava wrapper testing", async function () {

        // We get an instance of the USDC contract
        const USDCTokenContract = await ethers.getContractAt("IUSDC", USDC)
        const WETHContract = await ethers.getContractAt("IWETH", WETH);
        // const LendingPool = await ethers.getContractAt("ILendingPool", LendingPoolAddress)
        //makes sure owner has enough USDC balance
        console.log("amount==============", await account1.getBalance())
        console.log("amount==============", await WETHContract.balanceOf(account1.address))
        // if ((await WETHContract.balanceOf(account1.address)).lt("10000000000")) {
            
        // }

        await WETHContract.deposit({
          value: BigNumber.from("100000000000000000000")
        })

        console.log(await WETHContract.balanceOf(account1.address))

        // console.log("setting lendingPool")
        await Wrapper.setLendingPool(LendingPoolAddress);
        await WETHContract.connect(account1).approve(Wrapper.address, "20000000000000000000");
        await Wrapper.connect(account1).depositAndBorrow(WETHContract.address, "20000000000000000000", USDCTokenContract.address, "500000000");

        expect(await Wrapper.getUserDepositAmount(WETHContract.address, account1.address)).eq("20000000000000000000");
        expect(await Wrapper.getBorrowAmount(USDCTokenContract.address, account1.address)).eq("500000000");

        console.log("========================User balance of USDC===============", await USDCTokenContract.balanceOf(account1.address))
        console.log("========================User balance of WETH===============", await WETHContract.balanceOf(account1.address))

        await USDCTokenContract.connect(account1).approve(Wrapper.address, "20000000000000000000");
        await Wrapper.connect(account1).paybackAndWithdraw(WETHContract.address, "20000000000000000000", USDCTokenContract.address, "500000000");

        console.log("========================User balance of USDC after Withdraw===============", await USDCTokenContract.balanceOf(account1.address))
        console.log("========================User balance of WETH after Withdraw===============", await WETHContract.balanceOf(account1.address))
    });
});