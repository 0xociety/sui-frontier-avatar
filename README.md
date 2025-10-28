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
<td><code>0xcc0a65fd56d6c6d2386f91565052f9384073a692e24f7de2f5447e1ef6c07830</code></td>
<td><code>0x5c365d8cba5c5981e3713ac68a527d4eb90472092a8e7285bb68832f4d5aa213</code></td>
</tr>
<tr>
<td>Mainnet</td>
<td><code>NOT DEPLOYED YET</code></td>
<td><code>NOT DEPLOYED YET</code></td>
</tr>
</table>
