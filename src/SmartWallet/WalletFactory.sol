// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SignatureWallet_multi_v2} from "./SignatureWallet_multi_v2.sol";

/**
 * @title 钱包工厂合约
 * @author jonathan.ji
 * @notice 用于部署可升级多签钱包的工厂合约
 * @dev 功能：
 * - 使用 CREATE2 确定性部署
 * - 使用 ERC1967 代理模式
 * - 可以预计算钱包地址
 */
contract WalletFactory {
    /*//////////////////////////////////////////////////////////////
                                 常量
    //////////////////////////////////////////////////////////////*/

    /// @notice 钱包实现合约地址（所有代理共享）
    address public immutable implementation;

    /*//////////////////////////////////////////////////////////////
                                 事件
    //////////////////////////////////////////////////////////////*/

    /// @notice 钱包创建事件
    /// @param wallet 新创建的钱包代理地址
    /// @param owner 钱包所有者
    /// @param salt 用于 CREATE2 的 salt
    event WalletCreated(address indexed wallet, address indexed owner, bytes32 salt);

    /*//////////////////////////////////////////////////////////////
                                 构造函数
    //////////////////////////////////////////////////////////////*/

    /// @notice 部署实现合约
    constructor() {
        implementation = address(new SignatureWallet_multi_v2());
    }

    /*//////////////////////////////////////////////////////////////
                              核心函数
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 创建新的多签钱包
     * @param owner 钱包所有者
     * @param signers 初始签名者列表
     * @param threshold 签名阈值
     * @param salt 用于 CREATE2 的 salt（确定性地址）
     * @return wallet 新创建的钱包代理地址
     */
    function createWallet(
        address owner,
        address[] calldata signers,
        uint8 threshold,
        bytes32 salt
    ) external returns (address wallet) {
        bytes memory initData = _buildInitData(owner, signers, threshold);

        // 使用 CREATE2 部署 ERC1967 代理
        wallet = address(
            new ERC1967Proxy{salt: salt}(implementation, initData)
        );

        emit WalletCreated(wallet, owner, salt);
    }

    /**
     * @notice 预计算钱包地址（不实际部署）
     * @param owner 钱包所有者
     * @param signers 初始签名者列表
     * @param threshold 签名阈值
     * @param salt 用于 CREATE2 的 salt
     * @return 预计算的钱包地址
     */
    function getAddress(
        address owner,
        address[] calldata signers,
        uint8 threshold,
        bytes32 salt
    ) external view returns (address) {
        return _getAddress(owner, signers, threshold, salt);
    }

    /**
     * @notice 创建钱包（如果不存在）
     * @dev 如果钱包已存在，直接返回地址而不报错
     * @param owner 钱包所有者
     * @param signers 初始签名者列表
     * @param threshold 签名阈值
     * @param salt 用于 CREATE2 的 salt
     * @return wallet 钱包地址
     */
    function createWalletIfNotExists(
        address owner,
        address[] calldata signers,
        uint8 threshold,
        bytes32 salt
    ) external returns (address wallet) {
        wallet = _getAddress(owner, signers, threshold, salt);

        // 如果地址已有代码，说明钱包已存在
        if (wallet.code.length > 0) {
            return wallet;
        }

        bytes memory initData = _buildInitData(owner, signers, threshold);

        // 使用 CREATE2 部署
        wallet = address(
            new ERC1967Proxy{salt: salt}(implementation, initData)
        );

        emit WalletCreated(wallet, owner, salt);
    }

    /*//////////////////////////////////////////////////////////////
                              内部函数
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 构建初始化数据
     * @param owner 钱包所有者
     * @param signers 签名者列表
     * @param threshold 签名阈值
     * @return 编码后的初始化数据
     */
    function _buildInitData(
        address owner,
        address[] calldata signers,
        uint8 threshold
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(
            SignatureWallet_multi_v2.initialize,
            (owner, signers, threshold)
        );
    }

    /**
     * @notice 内部计算钱包地址
     * @param owner 钱包所有者
     * @param signers 签名者列表
     * @param threshold 签名阈值
     * @param salt 用于 CREATE2 的 salt
     * @return 预计算的钱包地址
     */
    function _getAddress(
        address owner,
        address[] calldata signers,
        uint8 threshold,
        bytes32 salt
    ) internal view returns (address) {
        bytes memory initData = _buildInitData(owner, signers, threshold);

        // 构建代理合约的创建字节码
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        // 计算 CREATE2 地址
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(proxyBytecode)
            )
        );

        return address(uint160(uint256(hash)));
    }
}
