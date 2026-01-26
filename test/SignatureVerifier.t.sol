
import "forge-std/Test.sol";
import "../src/Signature/SignatureVerifier.sol";

contract SingnatureVerifierTest is Test {
    SingnatureVerifier verifier;

    uint256 internal userPrivateKey;
    address internal user;

    function setUp() public {
        verifier = new SingnatureVerifier();

        // 1. 创建一个测试用的私钥和地址
        userPrivateKey = 0xA11CE;
        user = vm.addr(userPrivateKey);
    }

    function test_VerifySignature() public {
        string memory message = "iwant to use this address to collect my sentient airdrop because this adress is compromised.0x6fde4c19261e1495259a6f91861084bc5bff2ebe";

        // 2. 模拟链下签名过程

        // Step A: 计算消息 Hash
        bytes32 messageHash = keccak256(abi.encodePacked(message));

        // Step B: 加上以太坊前缀的 Hash (EIP-191) OpenZeppelin 的 MessageHashUtils 库逻辑等同于：
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        // Step C: 使用 vm.sign 进行签名 (得到 r, s, v)
        // Foundry模拟一个用户（持有私钥PK）对一个哈希值进行了签名
        // 生成的签名数据：27, 0x6cc...842e0, 0x408d...a4c3109
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, ethSignedMessageHash);

        // Step D: 将 r, s, v 打包成 bytes 格式的签名
        bytes memory signature = abi.encodePacked(r, s, v);

        // 3. 调用合约验证
        bool isValid = verifier.verify(user, message, signature);

        assertTrue(isValid, "Signature should be valid");
    }    
}