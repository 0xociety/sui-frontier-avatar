#[test_only]
module xociety_nft::xociety_frontier_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::test_utils;
    use std::string;
    use sui::vec_map;

    use xociety_nft::xociety_frontier::{Self, XocietyFrontier, Config, AdminCap, XOCIETY_FRONTIER};

    // Test addresses
    const ADMIN: address = @0xAD;
    const USER1: address = @0xA1;
    const USER2: address = @0xA2;

    // Helper function to initialize the module for testing
    fun init_for_test(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let otw = test_utils::create_one_time_witness<XOCIETY_FRONTIER>();
            xociety_frontier::test_init(otw, ts::ctx(scenario));
        };
    }

    // Helper function to create test NFT attributes
    fun create_test_attributes(): (vector<string::String>, vector<string::String>) {
        let keys = vector[
            string::utf8(b"trait_type"),
            string::utf8(b"rarity")
        ];
        let values = vector[
            string::utf8(b"Warrior"),
            string::utf8(b"Legendary")
        ];
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

        ts::next_tx(&mut scenario, ADMIN);
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
                ts::ctx(&mut scenario)
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

        ts::next_tx(&mut scenario, ADMIN);
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
                ts::ctx(&mut scenario)
            );

            let (attr_keys2, attr_values2) = create_test_attributes();

            // Try to mint second NFT with same token_id 1001 - should fail
            xociety_frontier::mint(
                &mut config,
                &admin_cap,
                1001,  // Duplicate!
                string::utf8(b"Test NFT 2"),
                string::utf8(b"Description 2"),
                string::utf8(b"https://example.com/2.png"),
                attr_keys2,
                attr_values2,
                USER2,
                ts::ctx(&mut scenario)
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

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<Config>(&scenario);

            // Pause the contract
            xociety_frontier::pause(&mut config, &admin_cap);

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
                ts::ctx(&mut scenario)
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

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<Config>(&scenario);

            // Initially not paused
            assert!(!xociety_frontier::is_paused(&config), 0);

            // Pause
            xociety_frontier::pause(&mut config, &admin_cap);
            assert!(xociety_frontier::is_paused(&config), 1);

            // Unpause
            xociety_frontier::unpause(&mut config, &admin_cap);
            assert!(!xociety_frontier::is_paused(&config), 2);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_add_admin_success() {
        let mut scenario = ts::begin(ADMIN);
        init_for_test(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<Config>(&scenario);

            // Add new admin
            xociety_frontier::add_admin(&mut config, &admin_cap, USER1, ts::ctx(&mut scenario));

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        // Verify USER1 received AdminCap
        ts::next_tx(&mut scenario, USER1);
        {
            assert!(ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_remove_admin_success() {
        let mut scenario = ts::begin(ADMIN);
        init_for_test(&mut scenario);

        // First add a second admin
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<Config>(&scenario);
            xociety_frontier::add_admin(&mut config, &admin_cap, USER1, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        // Now remove the second admin
        ts::next_tx(&mut scenario, USER1);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<Config>(&scenario);
            xociety_frontier::remove_admin(&mut config, admin_cap, ts::ctx(&mut scenario));
            ts::return_shared(config);
        };

        // Verify USER1 no longer has AdminCap
        ts::next_tx(&mut scenario, USER1);
        {
            assert!(!ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = xociety_frontier::ELastAdminCap)]
    fun test_remove_last_admin_fails() {
        let mut scenario = ts::begin(ADMIN);
        init_for_test(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<Config>(&scenario);

            // Try to remove the only admin - should fail
            xociety_frontier::remove_admin(&mut config, admin_cap, ts::ctx(&mut scenario));

            ts::return_shared(config);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = xociety_frontier::EAttributeLengthMismatch)]
    fun test_mint_mismatched_attributes_fails() {
        let mut scenario = ts::begin(ADMIN);
        init_for_test(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<Config>(&scenario);

            let keys = vector[string::utf8(b"key1"), string::utf8(b"key2")];
            let values = vector[string::utf8(b"value1")];  // Mismatched length!

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
                ts::ctx(&mut scenario)
            );

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(config);
        };

        ts::end(scenario);
    }
}
