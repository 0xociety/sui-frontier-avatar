#[test_only]
module xociety_nft::xociety_frontier_tests;

use multisig::multisig;
use std::string;
use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils;
use xociety_nft::xociety_frontier::{Self, XocietyFrontier, Config, AdminCap, XOCIETY_FRONTIER};

// Test addresses
const ADMIN: address = @0xAD;
const USER1: address = @0xA1;
const USER2: address = @0xA2;

// Helper function to get multisig address for testing (3/3 multisig)
fun get_test_multisig_address(): address {
  // 3/3 multisig: all 3 admins must approve
  let pks = vector[
    x"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
    x"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
    x"03774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cb",
  ];
  let weights = vector[1u8, 1u8, 1u8];
  let threshold = 3u16; // Require all 3 signatures

  multisig::derive_multisig_address_quiet(pks, weights, threshold)
}

// Helper function to get 2/3 multisig address
fun get_test_multisig_address_2of3(): address {
  // 2/3 multisig: any 2 of 3 admins must approve
  let pks = vector[
    x"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
    x"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
    x"03774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cb",
  ];
  let weights = vector[1u8, 1u8, 1u8];
  let threshold = 2u16; // Require any 2 signatures

  multisig::derive_multisig_address_quiet(pks, weights, threshold)
}

// Helper function to initialize the module for testing
fun init_for_test(scenario: &mut Scenario) {
  ts::next_tx(scenario, ADMIN);
  {
    let otw = test_utils::create_one_time_witness<XOCIETY_FRONTIER>();
    xociety_frontier::test_init(otw, ts::ctx(scenario));
  };

  // Configure 3/3 multisig (all tests use this by default)
  ts::next_tx(scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(scenario);
    let mut config = ts::take_shared<Config>(scenario);

    // Set up 3/3 multisig for testing
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

// Helper function to create test NFT attributes
fun create_test_attributes(): (vector<string::String>, vector<string::String>) {
  let keys = vector[string::utf8(b"trait_type"), string::utf8(b"rarity")];
  let values = vector[string::utf8(b"Warrior"), string::utf8(b"Legendary")];
  (keys, values)
}

#[test]
fun test_init_creates_admin_and_config() {
  let mut scenario = ts::begin(ADMIN);
  init_for_test(&mut scenario);

  // Check that AdminCap was created and sent to ADMIN
  ts::next_tx(&mut scenario, ADMIN);
  {
    assert!(ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    ts::return_to_sender(&scenario, admin_cap);
  };

  // Check that Config was created and shared
  ts::next_tx(&mut scenario, ADMIN);
  {
    let config = ts::take_shared<Config>(&scenario);
    assert!(!xociety_frontier::is_paused(&config), 1);
    ts::return_shared(config);
  };

  ts::end(scenario);
}

#[test]
fun test_mint_success() {
  let mut scenario = ts::begin(ADMIN);
  init_for_test(&mut scenario);

  // Transfer AdminCap to multisig address
  let multisig_addr = get_test_multisig_address();
  ts::next_tx(&mut scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    xociety_frontier::transfer_admin_cap_for_testing(admin_cap, multisig_addr);
  };

  // Mint as multisig
  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);
    let (attr_keys, attr_values) = create_test_attributes();

    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      1001,
      string::utf8(b"Test NFT"),
      string::utf8(b"Test Description"),
      string::utf8(b"https://example.com/image.png"),
      attr_keys,
      attr_values,
      USER1,
      ts::ctx(&mut scenario),
    );

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  // Verify NFT was sent to USER1
  ts::next_tx(&mut scenario, USER1);
  {
    assert!(ts::has_most_recent_for_sender<XocietyFrontier>(&scenario), 2);
    let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
    assert!(xociety_frontier::get_token_id(&nft) == 1001, 3);
    ts::return_to_sender(&scenario, nft);
  };

  ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = xociety_frontier::EDuplicateTokenId)]
fun test_mint_duplicate_token_id_fails() {
  let mut scenario = ts::begin(ADMIN);
  init_for_test(&mut scenario);

  // Transfer AdminCap to multisig address
  let multisig_addr = get_test_multisig_address();
  ts::next_tx(&mut scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    xociety_frontier::transfer_admin_cap_for_testing(admin_cap, multisig_addr);
  };

  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);
    let (attr_keys, attr_values) = create_test_attributes();

    // Mint first NFT with token_id 1001
    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      1001,
      string::utf8(b"Test NFT 1"),
      string::utf8(b"Description 1"),
      string::utf8(b"https://example.com/1.png"),
      attr_keys,
      attr_values,
      USER1,
      ts::ctx(&mut scenario),
    );

    let (attr_keys2, attr_values2) = create_test_attributes();

    // Try to mint second NFT with same token_id 1001 - should fail
    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      1001, // Duplicate!
      string::utf8(b"Test NFT 2"),
      string::utf8(b"Description 2"),
      string::utf8(b"https://example.com/2.png"),
      attr_keys2,
      attr_values2,
      USER2,
      ts::ctx(&mut scenario),
    );

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = xociety_frontier::EContractPaused)]
fun test_mint_when_paused_fails() {
  let mut scenario = ts::begin(ADMIN);
  init_for_test(&mut scenario);

  // Transfer AdminCap to multisig address
  let multisig_addr = get_test_multisig_address();
  ts::next_tx(&mut scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    xociety_frontier::transfer_admin_cap_for_testing(admin_cap, multisig_addr);
  };

  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);

    // Pause the contract
    xociety_frontier::pause(&mut config, &admin_cap, ts::ctx(&mut scenario));

    let (attr_keys, attr_values) = create_test_attributes();

    // Try to mint while paused - should fail
    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      1001,
      string::utf8(b"Test NFT"),
      string::utf8(b"Test Description"),
      string::utf8(b"https://example.com/image.png"),
      attr_keys,
      attr_values,
      USER1,
      ts::ctx(&mut scenario),
    );

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  ts::end(scenario);
}

#[test]
fun test_pause_unpause() {
  let mut scenario = ts::begin(ADMIN);
  init_for_test(&mut scenario);

  // Transfer AdminCap to multisig address
  let multisig_addr = get_test_multisig_address();
  ts::next_tx(&mut scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    xociety_frontier::transfer_admin_cap_for_testing(admin_cap, multisig_addr);
  };

  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);

    // Initially not paused
    assert!(!xociety_frontier::is_paused(&config), 0);

    // Pause
    xociety_frontier::pause(&mut config, &admin_cap, ts::ctx(&mut scenario));
    assert!(xociety_frontier::is_paused(&config), 1);

    // Unpause
    xociety_frontier::unpause(&mut config, &admin_cap, ts::ctx(&mut scenario));
    assert!(!xociety_frontier::is_paused(&config), 2);

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  ts::end(scenario);
}

// Note: Admin management tests removed
// Admin changes are now done through multisig configuration updates
// See test_multisig_2of3_configuration for multisig setup examples

#[test]
#[expected_failure(abort_code = xociety_frontier::EAttributeLengthMismatch)]
fun test_mint_mismatched_attributes_fails() {
  let mut scenario = ts::begin(ADMIN);
  init_for_test(&mut scenario);

  // Transfer AdminCap to multisig address
  let multisig_addr = get_test_multisig_address();
  ts::next_tx(&mut scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    xociety_frontier::transfer_admin_cap_for_testing(admin_cap, multisig_addr);
  };

  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);

    let keys = vector[string::utf8(b"key1"), string::utf8(b"key2")];
    let values = vector[string::utf8(b"value1")]; // Mismatched length!

    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      1001,
      string::utf8(b"Test NFT"),
      string::utf8(b"Test Description"),
      string::utf8(b"https://example.com/image.png"),
      keys,
      values,
      USER1,
      ts::ctx(&mut scenario),
    );

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  ts::end(scenario);
}

#[test]
fun test_multisig_2of3_configuration() {
  let mut scenario = ts::begin(ADMIN);

  // Initialize module
  ts::next_tx(&mut scenario, ADMIN);
  {
    let otw = test_utils::create_one_time_witness<XOCIETY_FRONTIER>();
    xociety_frontier::test_init(otw, ts::ctx(&mut scenario));
  };

  // Configure 2/3 multisig
  ts::next_tx(&mut scenario, ADMIN);
  {
    // Set up 2/3 multisig (any 2 of 3 admins can approve)
    let pks = vector[
      x"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
      x"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
      x"03774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cb",
    ];
    let weights = vector[1u8, 1u8, 1u8];
    let threshold = 2u16; // Require 2 out of 3 signatures

    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);

    xociety_frontier::set_multisig_config(
      &mut config,
      &admin_cap,
      pks,
      weights,
      threshold,
      ts::ctx(&mut scenario),
    );

    // Verify multisig is configured
    assert!(xociety_frontier::is_multisig_configured(&config), 0);

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  // Get the multisig address
  let multisig_addr = get_test_multisig_address_2of3();

  // Transfer AdminCap to multisig address
  ts::next_tx(&mut scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    xociety_frontier::transfer_admin_cap_for_testing(admin_cap, multisig_addr);
  };

  // Test minting with 2/3 multisig
  ts::next_tx(&mut scenario, multisig_addr);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);
    let (attr_keys, attr_values) = create_test_attributes();

    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      2001,
      string::utf8(b"Multisig NFT"),
      string::utf8(b"NFT minted with 2/3 multisig"),
      string::utf8(b"https://example.com/multisig.png"),
      attr_keys,
      attr_values,
      USER1,
      ts::ctx(&mut scenario),
    );

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  // Verify NFT was minted
  ts::next_tx(&mut scenario, USER1);
  {
    assert!(ts::has_most_recent_for_sender<XocietyFrontier>(&scenario), 1);
    let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
    assert!(xociety_frontier::get_token_id(&nft) == 2001, 2);
    ts::return_to_sender(&scenario, nft);
  };

  ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = xociety_frontier::ENotMultiSigSender)]
fun test_multisig_wrong_sender_fails() {
  let mut scenario = ts::begin(ADMIN);

  // Initialize module
  ts::next_tx(&mut scenario, ADMIN);
  {
    let otw = test_utils::create_one_time_witness<XOCIETY_FRONTIER>();
    xociety_frontier::test_init(otw, ts::ctx(&mut scenario));
  };

  // Configure 2/3 multisig
  ts::next_tx(&mut scenario, ADMIN);
  {
    let pks = vector[
      x"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
      x"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
      x"03774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cb",
    ];
    let weights = vector[1u8, 1u8, 1u8];
    let threshold = 2u16;

    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);

    xociety_frontier::set_multisig_config(
      &mut config,
      &admin_cap,
      pks,
      weights,
      threshold,
      ts::ctx(&mut scenario),
    );

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  // Try to mint from wrong address (ADMIN2) instead of multisig address
  // This should fail with ENotMultiSigSender
  ts::next_tx(&mut scenario, ADMIN);
  {
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    let mut config = ts::take_shared<Config>(&scenario);
    let (attr_keys, attr_values) = create_test_attributes();

    // This should fail because sender is ADMIN, not the multisig address
    xociety_frontier::mint(
      &mut config,
      &admin_cap,
      3001,
      string::utf8(b"Should Fail"),
      string::utf8(b"Should fail"),
      string::utf8(b"https://example.com/fail.png"),
      attr_keys,
      attr_values,
      USER1,
      ts::ctx(&mut scenario),
    );

    ts::return_to_sender(&scenario, admin_cap);
    ts::return_shared(config);
  };

  ts::end(scenario);
}
