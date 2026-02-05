# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
forge build              # Compile contracts
forge test               # Run all tests
forge test -vvv          # Verbose test output
forge test --match-test testFunctionName  # Run specific test
forge fmt                # Format code
forge fmt --check        # Check formatting (used in CI)
```

## Architecture Overview

This is a Foundry-based Solidity project implementing ERC-4337 (Account Abstraction) smart wallets and related infrastructure.

### Smart Wallet System (`src/SmartWallet/`)

The core of this project is a multi-signature smart wallet with ERC-4337 compliance:

- **SignatureWallet_v1.sol** - Single-owner wallet (non-upgradeable)
- **SignatureWallet_multi.sol** - M-of-N multi-sig (non-upgradeable)
- **SignatureWallet_multi_v2.sol** - M-of-N multi-sig with UUPS upgradeability (production version)
- **SignatureWallet_multi_v3.sol** - V2 + guardian recovery & spending limits (in development)
- **WalletFactory.sol** - CREATE2 factory for deterministic proxy deployment

**Key patterns:**
- UUPS upgradeable proxies (v2/v3 wallets)
- ERC1967Proxy for factory-deployed wallets
- Bitmap-based duplicate signer detection in multi-sig validation
- EntryPoint v0.7: `0x0000000071727De22E5E9d8BAf0edAc6f37da032`

### Other Contracts

- **StellaToken.sol** (`src/ERC20/`) - ERC20 token with owner mint/burn
- **AuthCaptureEscrow.sol** (`src/Payment/`) - Payment authorization/capture escrow
- **SignatureVerifier.sol** (`src/Signature/`) - ECDSA signature verification utility

## Import Remappings

```
account-abstraction/ → lib/account-abstraction/contracts/
@openzeppelin/contracts/ → lib/openzeppelin-contracts/contracts/
```

## CI

GitHub Actions runs on push/PR:
1. `forge fmt --check` - Format check
2. `forge build --sizes` - Build with size output
3. `forge test -vvv` - Tests with verbose output
