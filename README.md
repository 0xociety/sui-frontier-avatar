# Xociety Frontier Avatar - NFT Collection & Staking smart contract packages on SUI.

NFT collection and staking packages for Xociety Frontier Avatar.
Runs on Sui blockchain, uses Walrus storage, and implements standard Kiosk royalty system.

---

## 📁 Project Structure

```
sui/
├── packages/
│   ├── nft/                    # NFT Collection Package
│   │   ├── sources/
│   │   │   ├── XocietyFrontier.move           # NFT Core Logic
│   │   │   └── XocietyTransferPolicy.move     # Kiosk Royalty Policy
│   │   └── tests/
│   │       └── xociety_frontier_tests.move    # NFT Unit Tests
│   │
│   └── staking/                # NFT Staking Package
│       ├── sources/
│       │   └── StakeFrontier.move             # Staking Core Logic
│       └── tests/
│           ├── stake_frontier_tests.move      # Staking Unit Tests
│           └── integration_tests.move         # Integration Tests
```

---

## 🧪 Testing

### NFT Unit Tests

```bash
cd packages/nft
sui move test
```

**Test Coverage:**

- `test_init_creates_admin_and_config`: Initialization test
- `test_mint_success`: NFT mint success case
- `test_mint_duplicate_token_id_fails`: Duplicate token_id mint failure test
- `test_pause_unpause`: Pause functionality test
- `test_update_nft_success`: Metadata update test
- `test_add_remove_admin`: Admin add/remove test

### Staking Unit Tests

```bash
cd packages/staking
sui move test
```

**Test Coverage:**

- `test_init_creates_pool_and_admin`: Initialization test
- `test_stake_unstake_success`: Stake/unstake success case
- `test_batch_stake_unstake`: Batch operation test
- `test_max_stake_limit`: Maximum stake limit test
- `test_admin_stake`: Admin batch staking test
- `test_unstake_by_non_staker_fails`: Non-owner unstake failure test

### Integration Tests

```bash
cd packages/staking
sui move test --filter integration
```

**Test Scenarios:**

- Full flow: Mint NFT → Stake → Unstake
- Concurrent staking by multiple users
- Operation restrictions during pause state

## Package Deployed

<table>
<tr>
<th>Network</th>
<th>NFT collection</th>
<th>Staking</th>
</tr>
<tr>
<td>Testnet</td>
<td><code>0xcbc231288453379abec7784fe4fabe86048e47effa2b8da663f50a8950da04e4</code></td>
<td><code>0x29b61ab1b3ba267b89575df8ce3c74d68b081dc14a7a9b3c19dae0f68e4f0449</code></td>
</tr>
<tr>
<td>Mainnet</td>
<td><code>0x42c2cca562748d88490acb58109d4f8621ac3e170346aa60c6e52f7c50366546</code></td>
<td><code>0xbc484f89bb441717705524895db9f49c21b5a872849f2e2dd4a73df7dd10d5b8</code></td>
</tr>
</table>
