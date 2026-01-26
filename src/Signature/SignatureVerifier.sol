// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";


contract SingnatureVerifier {

    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    function verify(
        address _signer,
        string memory _message,
        bytes memory _signature
    ) public pure returns(bool){
        // 计算原始消息的Hash
        bytes32 messageHash = keccak256(abi.encodePacked(_message));

        // 2. 转换为 "以太坊签名消息 Hash" (Ethereum Signed Message Hash)
        // 这一步非常关键！MetaMask 签名时会自动加上前缀 "\x19Ethereum Signed Message:\n32"
        // 如果合约里不加这一步，恢复出的地址永远是错的。
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        // 3. 恢复签名者地址
        address recoveredAddress = ethSignedMessageHash.recover(_signature);

        // 4. 比对
        return recoveredAddress == _signer;
    }
}

