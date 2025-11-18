#[test_only]
module xociety_staking::stake_frontier_tests;

use std::string;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils;
use xociety_nft::xociety_frontier::{
  Self,
  XocietyFrontier,
  Config,
  AdminCap as NftAdminCap,
  XOCIETY_FRONTIER
};
use xociety_staking::stake_frontier::{Self, StakingPool, AdminCap, STAKE_FRONTIER};

// Test addresses
const ADMIN: address = @0xAD;
const USER1: address = @0xA1;
const USER2: address = @0xA2;

// Test multisig address (derived from the test public keys)
fun get_test_multisig_address(): address {
  use multisig::multisig;

  let pks = vector[
    x"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
    x"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
    x"03774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cb",
  ];
  let weights = vector[1u8, 1u8, 1u8];
  let threshold = 3u16;

  multisig::derive_multisig_address_quiet(pks, weights, threshold)
}

// Helper function to initialize NFT module with multisig
fun init_nft_for_test(scenario: &mut Scenario) {
  ts::next_tx(scenario, ADMIN);
  {
    let otw = test_utils::create_one_time_witness<XOCIETY_FRONTIER>();
    xociety_frontier::test_init(otw, ts::ctx(scenario));
  };

  // Configure multisig for NFT
  ts::next_tx(scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<NftAdminCap>(scenario);
    let mut config = ts::take_shared<Config>(scenario);

    let pks = vector[
      x"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
      x"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
      x"03774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cb",
    ];
    let weights = vector[1u8, 1u8, 1u8];
    let threshold = 3u16;

    xociety_frontier::set_multisig_config(
      &mut config,
      &admin_cap,
      pks,
      weights,
      threshold,
      ts::ctx(scenario),
    );

    ts::return_to_sender(scenario, admin_cap);
    ts::return_shared(config);
  };
}

// Helper function to initialize staking module with multisig config (but don't transfer AdminCap yet)
fun init_staking_for_test(scenario: &mut Scenario) {
  ts::next_tx(scenario, ADMIN);
  {
    let otw = test_utils::create_one_time_witness<STAKE_FRONTIER>();
    stake_frontier::test_init(otw, ts::ctx(scenario));
  };

  // Configure multisig for Staking
  ts::next_tx(scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(scenario);
    let mut pool = ts::take_shared<StakingPool>(scenario);

    let pks = vector[
      x"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
      x"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
      x"03774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cb",
    ];
    let weights = vector[1u8, 1u8, 1u8];
    let threshold = 3u16;

    stake_frontier::set_multisig_config(
      &mut pool,
      &admin_cap,
      pks,
      weights,
      threshold,
      ts::ctx(scenario),
    );

    ts::return_to_sender(scenario, admin_cap);
    ts::return_shared(pool);
  };
}

// Helper to transfer both NFT and Staking AdminCaps to multisig
fun transfer_admin_caps_to_multisig(scenario: &mut Scenario) {
  let multisig_addr = get_test_multisig_address();

  // Transfer NFT AdminCap
  ts::next_tx(scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<NftAdminCap>(scenario);
    xociety_frontier::transfer_admin_cap_for_testing(admin_cap, multisig_addr);
  };

  // Transfer Staking AdminCap
  ts::next_tx(scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(scenario);
    stake_frontier::transfer_admin_cap_for_testing(admin_cap, multisig_addr);
  };
}

// Helper function to mint an NFT (using multisig)
fun mint_nft(scenario: &mut Scenario, token_id: u64, recipient: address) {
  let multisig_addr = get_test_multisig_address();
  ts::next_tx(scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<NftAdminCap>(scenario);
    let mut config = ts::take_shared<Config>(scenario);

    let keys = vector[string::utf8(b"rarity")];
    let values = vector[string::utf8(b"Common")];

    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      token_id,
      string::utf8(b"Test NFT"),
      string::utf8(b"Description"),
      string::utf8(b"https://example.com/nft.png"),
      keys,
      values,
      recipient,
      ts::ctx(scenario),
    );

    ts::return_to_sender(scenario, admin_cap);
    ts::return_shared(config);
  };
}

#[test]
fun test_init_creates_pool_and_admin() {
  let mut scenario = ts::begin(ADMIN);
  init_staking_for_test(&mut scenario);

  // Check AdminCap was created
  ts::next_tx(&mut scenario, ADMIN);
  {
    assert!(ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    ts::return_to_sender(&scenario, admin_cap);
  };

  // Check StakingPool was created
  ts::next_tx(&mut scenario, ADMIN);
  {
    let pool = ts::take_shared<StakingPool>(&scenario);
    assert!(!stake_frontier::is_paused(&pool), 1);
    assert!(stake_frontier::get_max_stake_per_user(&pool) == 25, 2);
    ts::return_shared(pool);
  };

  ts::end(scenario);
}

#[test]
fun test_stake_unstake_success() {
  let mut scenario = ts::begin(ADMIN);
  init_nft_for_test(&mut scenario);
  init_staking_for_test(&mut scenario);
  transfer_admin_caps_to_multisig(&mut scenario);

  // Mint NFT to USER1
  mint_nft(&mut scenario, 1001, USER1);

  // Create clock
  ts::next_tx(&mut scenario, ADMIN);
  let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
  clock::set_for_testing(&mut clock, 1000000);

  // USER1 stakes the NFT
  ts::next_tx(&mut scenario, USER1);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
    let nft_id = object::id(&nft);

    stake_frontier::stake(&mut pool, vector[nft], &clock, ts::ctx(&mut scenario));

    // Verify staking
    assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 1, 0);
    let (staker, _timestamp) = stake_frontier::get_stake_info(&pool, nft_id);
    assert!(staker == USER1, 1);

    ts::return_shared(pool);
  };

  // USER1 unstakes the NFT
  ts::next_tx(&mut scenario, USER1);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);

    // Get all staked NFTs for USER1
    let all_stakes = stake_frontier::get_all_stakes(&pool);
    let mut nft_ids = vector::empty<ID>();
    let mut i = 0;
    while (i < vector::length(&all_stakes)) {
      let stake_info = vector::borrow(&all_stakes, i);
      let (nft_id, _token_id, staker, _timestamp) = stake_frontier::get_stake_info_parts(
        stake_info,
      );
      if (staker == USER1) {
        vector::push_back(&mut nft_ids, nft_id);
      };
      i = i + 1;
    };

    stake_frontier::unstake(&mut pool, nft_ids, &clock, ts::ctx(&mut scenario));

    // Verify unstaking
    assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 0, 2);

    ts::return_shared(pool);
  };

  // Verify USER1 has the NFT back
  ts::next_tx(&mut scenario, USER1);
  {
    assert!(ts::has_most_recent_for_sender<XocietyFrontier>(&scenario), 3);
    let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
    ts::return_to_sender(&scenario, nft);
  };

  clock::destroy_for_testing(clock);
  ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = stake_frontier::ENotStaker)]
fun test_unstake_by_non_staker_fails() {
  let mut scenario = ts::begin(ADMIN);
  init_nft_for_test(&mut scenario);
  init_staking_for_test(&mut scenario);
  transfer_admin_caps_to_multisig(&mut scenario);

  // Mint NFT to USER1
  mint_nft(&mut scenario, 1001, USER1);

  // Create clock
  ts::next_tx(&mut scenario, ADMIN);
  let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
  clock::set_for_testing(&mut clock, 1000000);

  // USER1 stakes the NFT
  ts::next_tx(&mut scenario, USER1);
  let nft_id = {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
    let id = object::id(&nft);

    stake_frontier::stake(&mut pool, vector[nft], &clock, ts::ctx(&mut scenario));

    ts::return_shared(pool);
    id
  };

  // USER2 tries to unstake USER1's NFT - should fail
  ts::next_tx(&mut scenario, USER2);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    stake_frontier::unstake(&mut pool, vector[nft_id], &clock, ts::ctx(&mut scenario));
    ts::return_shared(pool);
  };

  clock::destroy_for_testing(clock);
  ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = stake_frontier::EStakingPaused)]
fun test_stake_when_paused_fails() {
  let mut scenario = ts::begin(ADMIN);
  init_nft_for_test(&mut scenario);
  init_staking_for_test(&mut scenario);
  transfer_admin_caps_to_multisig(&mut scenario);

  // Mint NFT to USER1
  mint_nft(&mut scenario, 1001, USER1);

  // Create clock
  ts::next_tx(&mut scenario, ADMIN);
  let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

  // Pause the pool (using multisig)
  let multisig_addr = get_test_multisig_address();
  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    stake_frontier::pause(&mut pool, &admin_cap, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(pool);
  };

  // USER1 tries to stake - should fail
  ts::next_tx(&mut scenario, USER1);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
    stake_frontier::stake(&mut pool, vector[nft], &clock, ts::ctx(&mut scenario));
    ts::return_shared(pool);
  };

  clock::destroy_for_testing(clock);
  ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = stake_frontier::EMaxStakeCountExceeded)]
fun test_exceed_max_stake_fails() {
  let mut scenario = ts::begin(ADMIN);
  init_nft_for_test(&mut scenario);
  init_staking_for_test(&mut scenario);
  transfer_admin_caps_to_multisig(&mut scenario);

  // Mint 26 NFTs to USER1 (max is 25)
  let mut i = 0;
  while (i < 26) {
    mint_nft(&mut scenario, 1000 + i, USER1);
    i = i + 1;
  };

  // Create clock
  ts::next_tx(&mut scenario, ADMIN);
  let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

  // USER1 tries to stake all 26 NFTs - should fail
  ts::next_tx(&mut scenario, USER1);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let mut nfts = vector::empty<XocietyFrontier>();

    let mut j = 0;
    while (j < 26) {
      let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
      vector::push_back(&mut nfts, nft);
      j = j + 1;
    };

    stake_frontier::stake(&mut pool, nfts, &clock, ts::ctx(&mut scenario));
    ts::return_shared(pool);
  };

  clock::destroy_for_testing(clock);
  ts::end(scenario);
}

// Admin management tests removed - now using multisig authentication instead
