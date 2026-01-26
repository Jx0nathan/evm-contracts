// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {StellaToken} from "../../src/ERC20/StellaToken.sol";

// 执行命令：forge script script/ERC20/DeployERC20Script.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
contract DeployERC20Script is Script {
    function run() external {

        // 开始广播交易（这之后的操作都会被记录并发送到链上）
        vm.startBroadcast();

        // 部署合约
        StellaToken token = new StellaToken("Stella", "STA", 1_000_000);
        console.log("Token deployed at:", address(token));

        vm.stopBroadcast();
    }
}
