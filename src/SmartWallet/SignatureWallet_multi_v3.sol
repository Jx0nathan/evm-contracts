// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title 可升级多签智能钱包 V3
 * @author jonathan.ji
 * @notice 基于 ERC-4337 和 UUPS 代理模式的可升级多签钱包
 * @dev V3 新增功能：
 * - 版本号追踪
 * - Guardian 社交恢复机制
 * - 每日支出限额
 * - 紧急暂停功能
 */
contract SignatureWallet_multi_v3 is IAccount, Initializable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /*//////////////////////////////////////////////////////////////
                                 常量
    //////////////////////////////////////////////////////////////*/

    /// @notice 合约版本号
    string public constant VERSION = "3.0.0";

    /// @notice EntryPoint v0.7 官方地址（所有链都一样）
    address public constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /// @notice 签名验证成功返回值
    uint256 public constant SIG_VALIDATION_SUCCESS = 0;

    /// @notice 签名验证失败返回值
    uint256 public constant SIG_VALIDATION_FAILED = 1;

    /// @notice 恢复等待期（2天）
    uint256 public constant RECOVERY_PERIOD = 2 days;

    /*//////////////////////////////////////////////////////////////
                                 数据结构
    //////////////////////////////////////////////////////////////*/

    /// @notice 签名包装结构，包含签名者索引和签名数据
    struct SignatureWrapper {
        uint8 signerIndex;
        bytes signature;
    }

    /// @notice 恢复请求结构
    struct RecoveryRequest {
        address newOwner;
        uint256 executeAfter;
        bool executed;
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

    /// @notice 是否暂停
    bool public paused;

    /// @notice Guardian 地址（用于社交恢复）
    address public guardian;

    /// @notice 当前恢复请求
    RecoveryRequest public recoveryRequest;

    /// @notice 每日支出限额（wei）
    uint256 public dailyLimit;

    /// @notice 今日已支出金额
    uint256 public spentToday;

    /// @notice 上次重置日期（天数）
    uint256 public lastDay;

    /*//////////////////////////////////////////////////////////////
                                 错误定义
    //////////////////////////////////////////////////////////////*/

    error OnlyEntryPoint();
    error OnlyOwner();
    error OnlySelf();
    error OnlyGuardian();
    error CallFailed();
    error InvalidThreshold();
    error SignerAlreadyExists();
    error SignerNotExists();
    error DuplicateSigner(uint8 index);
    error ContractPaused();
    error NotPaused();
    error RecoveryNotReady();
    error RecoveryAlreadyExecuted();
    error NoRecoveryPending();
    error DailyLimitExceeded();
    error InvalidGuardian();

    /*//////////////////////////////////////////////////////////////
                                 事件
    //////////////////////////////////////////////////////////////*/

    event SignerAdded(uint8 indexed index, address indexed signer);
    event SignerRemoved(uint8 indexed index, address indexed signer);
    event ThresholdUpdated(uint8 newThreshold);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event RecoveryInitiated(address indexed guardian, address indexed newOwner, uint256 executeAfter);
    event RecoveryExecuted(address indexed oldOwner, address indexed newOwner);
    event RecoveryCancelled();
    event DailyLimitUpdated(uint256 newLimit);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                                 修饰符
    //////////////////////////////////////////////////////////////*/

    modifier onlyEntryPoint() {
        if (msg.sender != ENTRY_POINT) revert OnlyEntryPoint();
        _;
    }

    modifier onlyEntryPointOrSelf() {
        if (msg.sender != ENTRY_POINT && msg.sender != address(this)) {
            revert OnlyEntryPoint();
        }
        _;
    }

    /// @notice 只有合约自己可以调用（通过 execute 自调用）
    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier whenPaused() {
        if (!paused) revert NotPaused();
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
     * @notice 初始化多签钱包（用于新部署）
     * @param _owner 合约所有者
     * @param _signers 初始签名者列表
     * @param _threshold 签名阈值
     */
    function initialize(
        address _owner,
        address[] calldata _signers,
        uint8 _threshold
    ) external initializer {
        _initializeV3(_owner, _signers, _threshold, address(0), 0);
    }

    /**
     * @notice 从 V2 升级到 V3 的初始化
     * @dev 使用 reinitializer(3) 确保只能调用一次
     * @param _guardian 守护者地址（可选，传 address(0) 则不设置）
     * @param _dailyLimit 每日支出限额（可选，传 0 则不限制）
     */
    function initializeV3(
        address _guardian,
        uint256 _dailyLimit
    ) external reinitializer(3) {
        if (_guardian != address(0)) {
            guardian = _guardian;
            emit GuardianUpdated(address(0), _guardian);
        }

        if (_dailyLimit > 0) {
            dailyLimit = _dailyLimit;
            emit DailyLimitUpdated(_dailyLimit);
        }

        lastDay = block.timestamp / 1 days;
    }

    /**
     * @notice 内部初始化逻辑
     */
    function _initializeV3(
        address _owner,
        address[] calldata _signers,
        uint8 _threshold,
        address _guardian,
        uint256 _dailyLimit
    ) internal {
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

        if (_guardian != address(0)) {
            guardian = _guardian;
            emit GuardianUpdated(address(0), _guardian);
        }

        if (_dailyLimit > 0) {
            dailyLimit = _dailyLimit;
            emit DailyLimitUpdated(_dailyLimit);
        }

        lastDay = block.timestamp / 1 days;
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
    ) external onlyEntryPointOrSelf whenNotPaused returns (bytes memory result) {
        _checkDailyLimit(value);

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
    ) external onlyEntryPointOrSelf whenNotPaused {
        uint256 totalValue;
        for (uint256 i = 0; i < values.length; ++i) {
            totalValue += values[i];
        }
        _checkDailyLimit(totalValue);

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

    /**
     * @notice 转移所有权
     * @param _newOwner 新的所有者地址
     */
    function transferOwnership(address _newOwner) external onlySelf {
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                              暂停功能
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 暂停合约（紧急情况）
     * @dev Owner 或 Guardian 都可以暂停
     */
    function pause() external whenNotPaused {
        if (msg.sender != owner && msg.sender != guardian) {
            revert OnlyOwner();
        }
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice 解除暂停
     * @dev 只有通过自调用（多签验证后）可以解除暂停
     */
    function unpause() external onlySelf whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           Guardian 社交恢复
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 设置 Guardian
     * @param _guardian 新的 Guardian 地址
     */
    function setGuardian(address _guardian) external onlySelf {
        address oldGuardian = guardian;
        guardian = _guardian;
        emit GuardianUpdated(oldGuardian, _guardian);
    }

    /**
     * @notice Guardian 发起恢复请求
     * @param _newOwner 新的 Owner 地址
     */
    function initiateRecovery(address _newOwner) external onlyGuardian {
        if (_newOwner == address(0)) revert InvalidGuardian();

        recoveryRequest = RecoveryRequest({
            newOwner: _newOwner,
            executeAfter: block.timestamp + RECOVERY_PERIOD,
            executed: false
        });

        emit RecoveryInitiated(msg.sender, _newOwner, recoveryRequest.executeAfter);
    }

    /**
     * @notice 执行恢复（等待期结束后）
     */
    function executeRecovery() external onlyGuardian {
        RecoveryRequest storage request = recoveryRequest;

        if (request.newOwner == address(0)) revert NoRecoveryPending();
        if (request.executed) revert RecoveryAlreadyExecuted();
        if (block.timestamp < request.executeAfter) revert RecoveryNotReady();

        address oldOwner = owner;
        owner = request.newOwner;
        request.executed = true;

        emit RecoveryExecuted(oldOwner, request.newOwner);
    }

    /**
     * @notice 取消恢复请求
     * @dev Owner 可以直接调用（即使合约暂停），或通过多签自调用
     */
    function cancelRecovery() external {
        if (msg.sender != owner && msg.sender != address(this)) {
            revert OnlyOwner();
        }
        delete recoveryRequest;
        emit RecoveryCancelled();
    }

    /*//////////////////////////////////////////////////////////////
                              每日限额
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 设置每日支出限额
     * @param _dailyLimit 新的每日限额（wei），0 表示不限制
     */
    function setDailyLimit(uint256 _dailyLimit) external onlySelf {
        dailyLimit = _dailyLimit;
        emit DailyLimitUpdated(_dailyLimit);
    }

    /**
     * @notice 检查每日限额
     * @param _value 本次支出金额
     */
    function _checkDailyLimit(uint256 _value) internal {
        if (dailyLimit == 0) return; // 不限制

        uint256 today = block.timestamp / 1 days;

        // 新的一天，重置已支出金额
        if (today > lastDay) {
            lastDay = today;
            spentToday = 0;
        }

        if (spentToday + _value > dailyLimit) {
            revert DailyLimitExceeded();
        }

        spentToday += _value;
    }

    /*//////////////////////////////////////////////////////////////
                              UUPS 升级授权
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 授权合约升级
     * @dev 只有通过自调用（多签验证后）可以升级
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        if (msg.sender != address(this)) revert OnlySelf();
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
        SignatureWrapper[] memory signatures = abi.decode(
            signatureData,
            (SignatureWrapper[])
        );

        if (signatures.length != threshold) {
            return SIG_VALIDATION_FAILED;
        }

        uint256 usedSigners;
        bytes32 ethSignedHash = hash.toEthSignedMessageHash();

        for (uint256 i = 0; i < signatures.length; ++i) {
            uint8 signerIndex = signatures[i].signerIndex;

            uint256 mask = 1 << signerIndex;
            if (usedSigners & mask != 0) {
                revert DuplicateSigner(signerIndex);
            }
            usedSigners |= mask;

            address signer = signers[signerIndex];
            if (signer == address(0)) {
                return SIG_VALIDATION_FAILED;
            }

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

    /**
     * @notice 获取今日剩余可用额度
     * @return 剩余额度（wei）
     */
    function getRemainingDailyLimit() external view returns (uint256) {
        if (dailyLimit == 0) return type(uint256).max;

        uint256 today = block.timestamp / 1 days;
        if (today > lastDay) {
            return dailyLimit;
        }

        if (spentToday >= dailyLimit) return 0;
        return dailyLimit - spentToday;
    }

    /**
     * @notice 获取恢复请求详情
     * @return newOwner 新 Owner 地址
     * @return executeAfter 可执行时间戳
     * @return executed 是否已执行
     */
    function getRecoveryRequest() external view returns (
        address newOwner,
        uint256 executeAfter,
        bool executed
    ) {
        return (
            recoveryRequest.newOwner,
            recoveryRequest.executeAfter,
            recoveryRequest.executed
        );
    }

    /*//////////////////////////////////////////////////////////////
                              接收 ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
