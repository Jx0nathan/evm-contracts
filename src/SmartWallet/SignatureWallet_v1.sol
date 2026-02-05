// SPDX-License-Identifier: MIT
 pragma solidity ^0.8.23;

import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

 /**
   * @title 带签名验证的智能钱包
   * @author jonathan.ji
   * @notice SignatureWallet_v1
   * 新增功能：
   * - 实现 IAccount 接口
   * - 支持 EntryPoint 调用
   * - ECDSA 签名验证
   * 
   * 缺点：
   * - 单签名者：只有一个 owner，丢了私钥就完了
   * - 不可升级：代码写死，无法修改逻辑
   * - 无工厂：每次都要手动部署
   * 
   */
contract SignatureWallet_v1  {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /*//////////////////////////////////////////////////////////////
                                 常量
    //////////////////////////////////////////////////////////////*/

    /// @notice EntryPoint v0.7 官方地址（所有链都一样）
    address public constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    
    /// @notice 签名验证返回值
    uint256 public constant SIG_VALIDATION_SUCCESS = 0;

    /// @notice 签名验证返回值
    uint256 public constant SIG_VALIDATION_FAILED = 1;


    /*//////////////////////////////////////////////////////////////
                                 状态变量
    //////////////////////////////////////////////////////////////*/

    /// @notice 钱包所有者（签名者）
    address public owner;

    /*//////////////////////////////////////////////////////////////
                                 错误定义
    //////////////////////////////////////////////////////////////*/
    error OnlyEntryPoint();
    error OnlyOwner();
    error CallFailed();

    /*//////////////////////////////////////////////////////////////
                                 修饰符
    //////////////////////////////////////////////////////////////*/
    modifier onlyEntryPoint(){
        if (msg.sender != ENTRY_POINT) revert OnlyEntryPoint();
        _;
    }

    modifier onlyEntryPointOrOwner() {
        if (msg.sender != ENTRY_POINT && msg.sender != owner) {
              revert OnlyOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 构造函数
    //////////////////////////////////////////////////////////////*/
    /// @notice 构造函数
    /// @param _owner 合约所有者
    constructor(address _owner) {
        owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////
                           IAccount 接口实现
    //////////////////////////////////////////////////////////////*/

    /**
      * @notice 验证 UserOperation 的签名
      * @param userOp 用户操作
      * @param userOpHash 用户操作的哈希（由 EntryPoint 计算）
      * @param missingAccountFunds 需要预付给 EntryPoint 的 gas 费
      * @return validationData 0=成功, 1=失败
      */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
         
        // 1. 验证签名
        validationData = _validateSignature(userOpHash, userOp.signature);

        // 2. 预付 gas 费给 EntryPoint
        if (missingAccountFunds > 0) {
            //  Account 合约从自己的余额中，取出 missingAccountFunds 数量的 ETH，发送给 EntryPoint
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
      ) external onlyEntryPointOrOwner returns (bytes memory) {
          (bool success, bytes memory result) = target.call{value: value}(data);
          if (!success) revert CallFailed();
          return result;
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
                              内部函数
    //////////////////////////////////////////////////////////////*/

    /**
       * @notice 验证签名
       * @param hash 要验证的哈希
       * @param signature 签名数据
       * @return 0=有效, 1=无效
       */
    function _validateSignature(
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (uint256){
         // 将 hash 转换成 EIP-191 格式的签名消息
         // 这是以太坊签名的标准格式 "\x19Ethereum Signed Message:\n32" + hash
         bytes32 ethSignedHash = hash.toEthSignedMessageHash();

        // 从签名中恢复签名者地址
         address recoveredSigner = ethSignedHash.recover(signature);

        // 比较恢复的地址和 owner
         if( recoveredSigner == owner){
            return SIG_VALIDATION_SUCCESS; // 0
        }
        return SIG_VALIDATION_FAILED; // 1
    }

    /*//////////////////////////////////////////////////////////////
                              接收 ETH
    //////////////////////////////////////////////////////////////*/
    /// @notice 接收 ETH
    receive() external payable {}
}
