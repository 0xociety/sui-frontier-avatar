#[test_only]
module xociety_staking::integration_tests;

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
use xociety_staking::stake_frontier::{Self, StakingPool, AdminCap as StakeAdminCap, STAKE_FRONTIER};

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

// Setup helper: Initialize both modules with multisig
fun setup(scenario: &mut Scenario) {
  // Init NFT module
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

  // Transfer NFT AdminCap to multisig
  ts::next_tx(scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<NftAdminCap>(scenario);
    xociety_frontier::transfer_admin_cap_for_testing(admin_cap, get_test_multisig_address());
  };

  // Init Staking module
  ts::next_tx(scenario, ADMIN);
  {
    let otw = test_utils::create_one_time_witness<STAKE_FRONTIER>();
    stake_frontier::test_init(otw, ts::ctx(scenario));
  };

  // Configure multisig for Staking
  ts::next_tx(scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<StakeAdminCap>(scenario);
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

  // Transfer Staking AdminCap to multisig
  ts::next_tx(scenario, ADMIN);
  {
    let stake_admin_cap = ts::take_from_sender<StakeAdminCap>(scenario);
    stake_frontier::transfer_admin_cap_for_testing(stake_admin_cap, get_test_multisig_address());
  };
}

// Helper: Mint NFT to a user (using multisig)
fun mint_nft_to_user(scenario: &mut Scenario, token_id: u64, recipient: address) {
  let multisig_addr = get_test_multisig_address();
  ts::next_tx(scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<NftAdminCap>(scenario);
    let mut config = ts::take_shared<Config>(scenario);

    let keys = vector[string::utf8(b"rarity"), string::utf8(b"power")];
    let values = vector[string::utf8(b"Epic"), string::utf8(b"100")];

    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      token_id,
      string::utf8(b"Frontier NFT"),
      string::utf8(b"A powerful frontier NFT"),
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
fun test_full_flow_mint_stake_unstake() {
  let mut scenario = ts::begin(ADMIN);
  setup(&mut scenario);

  // Create clock
  ts::next_tx(&mut scenario, ADMIN);
  let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
  clock::set_for_testing(&mut clock, 1000000);

  // Step 1: Mint 3 NFTs to USER1
  mint_nft_to_user(&mut scenario, 2001, USER1);
  mint_nft_to_user(&mut scenario, 2002, USER1);
  mint_nft_to_user(&mut scenario, 2003, USER1);

  // Verify USER1 has 3 NFTs
  ts::next_tx(&mut scenario, USER1);
  {
    let nft1 = ts::take_from_sender<XocietyFrontier>(&scenario);
    let nft2 = ts::take_from_sender<XocietyFrontier>(&scenario);
    let nft3 = ts::take_from_sender<XocietyFrontier>(&scenario);

    // Verify all 3 NFTs exist (order not guaranteed)
    let id1 = xociety_frontier::get_token_id(&nft1);
    let id2 = xociety_frontier::get_token_id(&nft2);
    let id3 = xociety_frontier::get_token_id(&nft3);
    assert!(id1 >= 2001 && id1 <= 2003, 0);
    assert!(id2 >= 2001 && id2 <= 2003, 1);
    assert!(id3 >= 2001 && id3 <= 2003, 2);

    ts::return_to_sender(&scenario, nft1);
    ts::return_to_sender(&scenario, nft2);
    ts::return_to_sender(&scenario, nft3);
  };

  // Step 2: USER1 stakes all 3 NFTs
  ts::next_tx(&mut scenario, USER1);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let nft1 = ts::take_from_sender<XocietyFrontier>(&scenario);
    let nft2 = ts::take_from_sender<XocietyFrontier>(&scenario);
    let nft3 = ts::take_from_sender<XocietyFrontier>(&scenario);

    stake_frontier::stake(&mut pool, vector[nft1, nft2, nft3], &clock, ts::ctx(&mut scenario));

    // Verify staking count
    assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 3, 3);

    ts::return_shared(pool);
  };

  // Step 3: Advance time
  clock::set_for_testing(&mut clock, 2000000);

  // Step 4: USER1 unstakes 2 NFTs
  ts::next_tx(&mut scenario, USER1);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let user_stakes = stake_frontier::get_user_stakes(&pool, USER1);

    assert!(vector::length(&user_stakes) == 3, 4);

    // Unstake first 2 NFTs
    let mut nft_ids = vector::empty<ID>();
    let mut i = 0;
    while (i < 2) {
      let stake_info = vector::borrow(&user_stakes, i);
      let (nft_id, _, _) = stake_frontier::get_user_stake_info_parts(stake_info);
      vector::push_back(&mut nft_ids, nft_id);
      i = i + 1;
    };

    stake_frontier::unstake(&mut pool, nft_ids, &clock, ts::ctx(&mut scenario));

    // Verify 1 NFT still staked
    assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 1, 5);

    ts::return_shared(pool);
  };

  // Verify USER1 has 2 NFTs back
  ts::next_tx(&mut scenario, USER1);
  {
    let nft1 = ts::take_from_sender<XocietyFrontier>(&scenario);
    let nft2 = ts::take_from_sender<XocietyFrontier>(&scenario);

    ts::return_to_sender(&scenario, nft1);
    ts::return_to_sender(&scenario, nft2);
  };

  // Step 5: USER1 unstakes the last NFT
  ts::next_tx(&mut scenario, USER1);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let user_stakes = stake_frontier::get_user_stakes(&pool, USER1);

    let mut nft_ids = vector::empty<ID>();
    let stake_info = vector::borrow(&user_stakes, 0);
    let (nft_id, _, _) = stake_frontier::get_user_stake_info_parts(stake_info);
    vector::push_back(&mut nft_ids, nft_id);

    stake_frontier::unstake(&mut pool, nft_ids, &clock, ts::ctx(&mut scenario));

    // Verify all NFTs unstaked
    assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 0, 6);

    ts::return_shared(pool);
  };

  // Verify USER1 has all 3 NFTs back
  ts::next_tx(&mut scenario, USER1);
  {
    let nft3 = ts::take_from_sender<XocietyFrontier>(&scenario);
    ts::return_to_sender(&scenario, nft3);
  };

  clock::destroy_for_testing(clock);
  ts::end(scenario);
}

#[test]
fun test_multiple_users_staking() {
  let mut scenario = ts::begin(ADMIN);
  setup(&mut scenario);

  // Create clock
  ts::next_tx(&mut scenario, ADMIN);
  let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
  clock::set_for_testing(&mut clock, 1000000);

  // Mint NFTs to USER1 and USER2
  mint_nft_to_user(&mut scenario, 3001, USER1);
  mint_nft_to_user(&mut scenario, 3002, USER1);
  mint_nft_to_user(&mut scenario, 3003, USER2);
  mint_nft_to_user(&mut scenario, 3004, USER2);

  // USER1 stakes 2 NFTs
  ts::next_tx(&mut scenario, USER1);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let nft1 = ts::take_from_sender<XocietyFrontier>(&scenario);
    let nft2 = ts::take_from_sender<XocietyFrontier>(&scenario);

    stake_frontier::stake(&mut pool, vector[nft1, nft2], &clock, ts::ctx(&mut scenario));

    assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 2, 0);
    assert!(stake_frontier::get_staked_count_for_user(&pool, USER2) == 0, 1);

    ts::return_shared(pool);
  };

  // USER2 stakes 2 NFTs
  ts::next_tx(&mut scenario, USER2);
  {
    let mut pool = ts::take_shared<StakingPool>(&scenario);
    let nft3 = ts::take_from_sender<XocietyFrontier>(&scenario);
    let nft4 = ts::take_from_sender<XocietyFrontier>(&scenario);

    stake_frontier::stake(&mut pool, vector[nft3, nft4], &clock, ts::ctx(&mut scenario));

    assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 2, 2);
    assert!(stake_frontier::get_staked_count_for_user(&pool, USER2) == 2, 3);

    ts::return_shared(pool);
  };

  // Verify total stakes
  ts::next_tx(&mut scenario, ADMIN);
  {
    let pool = ts::take_shared<StakingPool>(&scenario);
    let all_stakes = stake_frontier::get_all_stakes(&pool);
    assert!(vector::length(&all_stakes) == 4, 4);
    ts::return_shared(pool);
  };

  clock::destroy_for_testing(clock);
  ts::end(scenario);
}

#[test]
fun test_pause_unpause_workflow() {
  let mut scenario = ts::begin(ADMIN);
  setup(&mut scenario);
  let multisig_addr = get_test_multisig_address();

  // Pause NFT minting
  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<NftAdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);

    xociety_frontier::pause(&mut config, &admin_cap, ts::ctx(&mut scenario));
    assert!(xociety_frontier::is_paused(&config), 0);

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  // Unpause NFT minting
  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<NftAdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);

    xociety_frontier::unpause(&mut config, &admin_cap, ts::ctx(&mut scenario));
    assert!(!xociety_frontier::is_paused(&config), 1);

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  // Pause staking
  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<StakeAdminCap>(&scenario);
    let mut pool = ts::take_shared<StakingPool>(&scenario);

    stake_frontier::pause(&mut pool, &admin_cap, ts::ctx(&mut scenario));
    assert!(stake_frontier::is_paused(&pool), 2);

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(pool);
  };

  // Unpause staking
  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<StakeAdminCap>(&scenario);
    let mut pool = ts::take_shared<StakingPool>(&scenario);

    stake_frontier::unpause(&mut pool, &admin_cap, ts::ctx(&mut scenario));
    assert!(!stake_frontier::is_paused(&pool), 3);

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(pool);
  };

  ts::end(scenario);
}

// Admin management test removed - now using multisig authentication
