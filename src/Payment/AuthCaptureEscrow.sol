// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AuthCaptureEscrow {


    /// @notice Payment info, contains all information required to authorize and capture a unique payment
    struct PaymentInfo {
        /// @dev Entity responsible for driving payment flow
        address operator;
        /// @dev The payer's address authorizing the payment
        address payer;
        /// @dev Address that receives the payment (minus fees)
        address receiver;
        /// @dev The token contract address
        address token;
        /// @dev The amount of tokens that can be authorized
        uint120 maxAmount;
        /// @dev Timestamp when the payer's pre-approval can no longer authorize payment
        uint48 preApprovalExpiry;
        /// @dev Timestamp when an authorization can no longer be captured and the payer can reclaim from escrow
        uint48 authorizationExpiry;
        /// @dev Timestamp when a successful payment can no longer be refunded
        uint48 refundExpiry;
        /// @dev Minimum fee percentage in basis points
        uint16 minFeeBps;
        /// @dev Maximum fee percentage in basis points
        uint16 maxFeeBps;
        /// @dev Address that receives the fee portion of payments, if 0 then operator can set at capture
        address feeReceiver;
        /// @dev A source of entropy to ensure unique hashes across different payments
        uint256 salt;
    }

    uint16 internal constant _MAX_FEE_BPS = 10_000;


    /// @notice Error thrown when an amount exceeds the maximum allowed
    error ExceedsMaxAmount(uint256 amount, uint256 maxAmount);

    /// @notice Authorization attempted after pre-approval expiry
    error AfterPreApprovalExpiry(uint48 timestamp, uint48 expiry);

    /// @notice Expiry timestamps violate preApproval <= authorization <= refund
    error InvalidExpiries(uint48 preApproval, uint48 authorization, uint48 refund);

    /// @notice Fee bips overflows 10_000 maximum
    error FeeBpsOverflow(uint16 feeBps);

    /// @notice Fee bps range invalid due to min > max
    error InvalidFeeBpsRange(uint16 minFeeBps, uint16 maxFeeBps);

    /// @notice Validates the payment information and amount
    /// 
    /// @param paymentInfo The payment information
    /// @param amount Token amount to validate against
    function _validatePayment(PaymentInfo calldata paymentInfo, uint256 amount) internal view {
        uint120 maxAmount = paymentInfo.maxAmount;
        uint48 preApprovalExp = paymentInfo.preApprovalExpiry;
        uint48 authorizationExp = paymentInfo.authorizationExpiry;
        uint48 refundExp = paymentInfo.refundExpiry;
        uint16 minFeeBps = paymentInfo.minFeeBps;
        uint16 maxFeeBps = paymentInfo.maxFeeBps;

        // Current timestamp , 使用uint48不会溢出，同时也能节省Gas
        uint48 currentTimestamp = uint48(block.timestamp);

        // Check amount does not exceed maximum
        if (amount > maxAmount) revert ExceedsMaxAmount(amount, maxAmount);

        // Timestamp comparisons cannot overflow uint48
        if (currentTimestamp > preApprovalExp) revert AfterPreApprovalExpiry(currentTimestamp, preApprovalExp);

        // Check expiry timestamps properly ordered
        if (preApprovalExp > authorizationExp || authorizationExp > refundExp) {
            revert InvalidExpiries(preApprovalExp, authorizationExp, refundExp);
        }

        // Check fee bps do not exceed maximum value
        if (maxFeeBps > _MAX_FEE_BPS) revert FeeBpsOverflow(maxFeeBps);

        // Check min fee bps does not exceed max fee
        if (minFeeBps > maxFeeBps) revert InvalidFeeBpsRange(minFeeBps, maxFeeBps);
    }

}
