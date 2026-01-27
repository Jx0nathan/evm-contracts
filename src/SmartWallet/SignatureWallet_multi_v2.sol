// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title 可升级多签智能钱包 V2
 * @author jonathan.ji
 * @notice 基于 ERC-4337 和 UUPS 代理模式的可升级多签钱包
 * @dev 功能：
 * - M-of-N 多签机制
 * - UUPS 可升级模式
 * - 添加/移除签名者
 * - 更新阈值
 */
contract SignatureWallet_multi_v2 is IAccount, Initializable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /*//////////////////////////////////////////////////////////////
                                 常量
    //////////////////////////////////////////////////////////////*/

    /// @notice EntryPoint v0.7 官方地址（所有链都一样）
    address public constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /// @notice 签名验证成功返回值
    uint256 public constant SIG_VALIDATION_SUCCESS = 0;

    /// @notice 签名验证失败返回值
    uint256 public constant SIG_VALIDATION_FAILED = 1;

    /*//////////////////////////////////////////////////////////////
                                 数据结构
    //////////////////////////////////////////////////////////////*/

    /// @notice 签名包装结构，包含签名者索引和签名数据
    struct SignatureWrapper {
        uint8 signerIndex;
        bytes signature;
    }

    /*//////////////////////////////////////////////////////////////
                                 状态变量
    //////////////////////////////////////////////////////////////*/

    /// @notice 合约所有者（可管理升级）
    address public owner;

    /// @notice 需要的签名数量阈值
    uint8 public threshold;

    /// @notice 签名者总数
    uint8 public signerCount;

    /// @notice index => 签名者地址
    mapping(uint8 => address) public signers;

    /*//////////////////////////////////////////////////////////////
                                 错误定义
    //////////////////////////////////////////////////////////////*/

    error OnlyEntryPoint();
    error OnlyOwner();
    error OnlySelf();
    error CallFailed();
    error InvalidThreshold();
    error SignerAlreadyExists();
    error SignerNotExists();
    error DuplicateSigner(uint8 index);

    /*//////////////////////////////////////////////////////////////
                                 事件
    //////////////////////////////////////////////////////////////*/

    event SignerAdded(uint8 indexed index, address indexed signer);
    event SignerRemoved(uint8 indexed index, address indexed signer);
    event ThresholdUpdated(uint8 newThreshold);

    /*//////////////////////////////////////////////////////////////
                                 修饰符
    //////////////////////////////////////////////////////////////*/

    modifier onlyEntryPoint() {
        if (msg.sender != ENTRY_POINT) revert OnlyEntryPoint();
        _;
    }

    modifier onlyEntryPointOrOwner() {
        if (msg.sender != ENTRY_POINT && msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    /// @notice 只有合约自己可以调用（通过 execute 自调用）
    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              构造函数 & 初始化
    //////////////////////////////////////////////////////////////*/

    /// @notice 禁用实现合约的初始化
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化多签钱包
     * @param _owner 合约所有者
     * @param _signers 初始签名者列表
     * @param _threshold 签名阈值
     */
    function initialize(
        address _owner,
        address[] calldata _signers,
        uint8 _threshold
    ) external initializer {
        if (_threshold == 0 || _threshold > _signers.length) {
            revert InvalidThreshold();
        }

        owner = _owner;
        threshold = _threshold;
        signerCount = uint8(_signers.length);

        for (uint8 i = 0; i < _signers.length; ++i) {
            signers[i] = _signers[i];
            emit SignerAdded(i, _signers[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           IAccount 接口实现
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 验证 UserOperation 的签名
     * @param userOp 用户操作（打包的交易）
     * @param userOpHash 操作哈希（由 EntryPoint 计算）
     * @param missingAccountFunds 需要预付给 EntryPoint 的 gas 费
     * @return validationData 0=成功, 1=失败
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
        validationData = _validateMultiSignature(userOpHash, userOp.signature);

        // 如果账户余额不足以支付 gas 费用，向 EntryPoint 合约补充所需资金
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            // 忽略失败，EntryPoint 会处理
            (success);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              执行函数
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 执行单个调用
     * @param target 被调用的目标合约地址
     * @param value 随调用转出的 ETH 数量（wei）
     * @param data 调用数据（calldata）
     * @return result 外部调用返回的数据
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyEntryPointOrOwner returns (bytes memory result) {
        bool success;
        (success, result) = target.call{value: value}(data);
        if (!success) revert CallFailed();
    }

    /**
     * @notice 批量执行多个调用
     * @param targets 被调用的目标合约地址数组
     * @param values 每个调用对应转出的 ETH 数量（wei）
     * @param datas 每个调用对应的 calldata
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyEntryPointOrOwner {
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success,) = targets[i].call{value: values[i]}(datas[i]);
            if (!success) revert CallFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          签名者管理（只能自调用）
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 添加签名者
     * @dev 只能通过 execute(address(this), 0, abi.encodeCall(this.addSigner, (_signer, _index))) 调用
     * @param _signer 新签名者地址
     * @param _index 签名者索引
     */
    function addSigner(address _signer, uint8 _index) external onlySelf {
        if (signers[_index] != address(0)) revert SignerAlreadyExists();

        signers[_index] = _signer;
        signerCount++;

        emit SignerAdded(_index, _signer);
    }

    /**
     * @notice 移除签名者
     * @param _index 要移除的签名者索引
     */
    function removeSigner(uint8 _index) external onlySelf {
        address signer = signers[_index];
        if (signer == address(0)) revert SignerNotExists();

        // 移除后签名者数量不能小于阈值
        if (signerCount - 1 < threshold) revert InvalidThreshold();

        delete signers[_index];
        signerCount--;

        emit SignerRemoved(_index, signer);
    }

    /**
     * @notice 更新阈值
     * @param _newThreshold 新的签名阈值
     */
    function updateThreshold(uint8 _newThreshold) external onlySelf {
        if (_newThreshold == 0 || _newThreshold > signerCount) {
            revert InvalidThreshold();
        }

        threshold = _newThreshold;

        emit ThresholdUpdated(_newThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                              UUPS 升级授权
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 授权合约升级
     * @dev 只有 owner 可以升级合约
     * @param newImplementation 新实现合约地址（未使用但需要保留参数）
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation); // 消除未使用参数警告
        if (msg.sender != owner) revert OnlyOwner();
    }

    /*//////////////////////////////////////////////////////////////
                              内部函数
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 验证多签
     * @param hash 要验证的哈希
     * @param signatureData 编码的签名数组
     * @return 0=有效, 1=无效
     */
    function _validateMultiSignature(
        bytes32 hash,
        bytes calldata signatureData
    ) internal view returns (uint256) {
        // 解码签名数组
        SignatureWrapper[] memory signatures = abi.decode(
            signatureData,
            (SignatureWrapper[])
        );

        // 签名数量必须等于阈值
        if (signatures.length != threshold) {
            return SIG_VALIDATION_FAILED;
        }

        // 用于检测重复签名的位图
        uint256 usedSigners;
        bytes32 ethSignedHash = hash.toEthSignedMessageHash();

        for (uint256 i = 0; i < signatures.length; ++i) {
            uint8 signerIndex = signatures[i].signerIndex;

            // 检查是否重复使用同一个签名者（位图检测）
            uint256 mask = 1 << signerIndex;
            if (usedSigners & mask != 0) {
                revert DuplicateSigner(signerIndex);
            }
            usedSigners |= mask;

            // 获取签名者地址
            address signer = signers[signerIndex];
            if (signer == address(0)) {
                return SIG_VALIDATION_FAILED;
            }

            // 验证签名
            address recovered = ethSignedHash.recover(signatures[i].signature);
            if (recovered != signer) {
                return SIG_VALIDATION_FAILED;
            }
        }

        return SIG_VALIDATION_SUCCESS;
    }

    /*//////////////////////////////////////////////////////////////
                              查询函数
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 获取指定索引的签名者地址
     * @param index 签名者索引
     * @return 签名者地址
     */
    function getSigner(uint8 index) external view returns (address) {
        return signers[index];
    }

    /*//////////////////////////////////////////////////////////////
                              接收 ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
