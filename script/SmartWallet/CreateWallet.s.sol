// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {WalletFactory} from "../../src/SmartWallet/WalletFactory.sol";

/**
 * @title 通过工厂创建钱包
 * @notice 使用已部署的 WalletFactory 创建新的多签钱包
 *
 * 使用方法:
 *   FACTORY=0x... \
 *   OWNER=0x... \
 *   SIGNERS=0x...,0x...,0x... \
 *   THRESHOLD=2 \
 *   SALT=0x0000000000000000000000000000000000000000000000000000000000000001 \
 *   forge script script/SmartWallet/CreateWallet.s.sol:CreateWallet \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast
 */
contract CreateWallet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 读取参数
        address factoryAddr = vm.envAddress("FACTORY");
        address owner = vm.envAddress("OWNER");
        uint8 threshold = uint8(vm.envUint("THRESHOLD"));
        bytes32 salt = vm.envBytes32("SALT");

        // 解析签名者列表（逗号分隔）
        string memory signersStr = vm.envString("SIGNERS");
        address[] memory signers = _parseSigners(signersStr);

        WalletFactory factory = WalletFactory(factoryAddr);

        // 预计算地址
        address predictedAddr = factory.getAddress(owner, signers, threshold, salt);
        console.log("Predicted wallet address:", predictedAddr);

        vm.startBroadcast(deployerPrivateKey);

        address wallet = factory.createWallet(owner, signers, threshold, salt);

        console.log("Wallet created at:", wallet);

        vm.stopBroadcast();
    }

    function _parseSigners(string memory signersStr) internal pure returns (address[] memory) {
        // 简单实现：假设最多 10 个签名者
        address[] memory temp = new address[](10);
        uint256 count = 0;

        bytes memory strBytes = bytes(signersStr);
        uint256 start = 0;

        for (uint256 i = 0; i <= strBytes.length; i++) {
            if (i == strBytes.length || strBytes[i] == ",") {
                if (i > start) {
                    bytes memory addrBytes = new bytes(i - start);
                    for (uint256 j = start; j < i; j++) {
                        addrBytes[j - start] = strBytes[j];
                    }
                    temp[count] = vm.parseAddress(string(addrBytes));
                    count++;
                }
                start = i + 1;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }
        return result;
    }
}
