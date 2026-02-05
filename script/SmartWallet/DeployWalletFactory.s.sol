// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {WalletFactory} from "../../src/SmartWallet/WalletFactory.sol";

/**
 * @title 部署钱包工厂合约
 * @notice 部署 WalletFactory，会自动部署 SignatureWallet_multi_v2 作为实现合约
 *
 * 使用方法:
 *   forge script script/SmartWallet/DeployWalletFactory.s.sol:DeployWalletFactory \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployWalletFactory is Script {
    function run() external {
        // 从环境变量读取私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 部署工厂合约（会自动部署实现合约）
        WalletFactory factory = new WalletFactory();

        console.log("WalletFactory deployed at:", address(factory));
        console.log("Implementation deployed at:", factory.implementation());

        vm.stopBroadcast();
    }
}
